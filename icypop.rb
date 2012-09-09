#!/usr/bin/ruby

puts "Starting Icypop"

# require your gems as usual
require "rubygems"
require "bundler/setup"
require "fog"
require 'fog/aws/glacier'
require "aws"
require "yaml"


def help
    puts ""
    puts "Usage: #{__FILE__} <file_to_upload> <description>"
    puts ""
end



# Get command line arguments
somefile = ARGV[0]
somedescription = ARGV[1]

#ARGV.each do |a|
#  puts "Argument: #{a}"
#end

if somefile.nil? 
    help
    abort "File Not Specified"
end

unless File.exists?(somefile)
    help
    abort "File Does Not Exist: #{somefile}"
else
    puts "File to Upload: #{somefile}"
end

if somedescription.nil? 
    help
    abort "Description Not Specified"
end

puts "Reading Environment for Icypop"

# Read settings
current_environment = "production"
raw_config = File.read("icypop.yml")
APP_CONFIG = YAML.load(raw_config)[current_environment]

# Set variables
aws_access_key_id = APP_CONFIG[:aws_access_key_id]
aws_secret_access_key = APP_CONFIG[:aws_secret_access_key]
aws_region = APP_CONFIG[:aws_region]
glacier_vault = APP_CONFIG[:glacier_vault]
glacier_multipart_chunk_size = APP_CONFIG[:glacier_multipart_chunk_size]
target_dynamo_db = APP_CONFIG[:target_dynamo_db]
glacier_sns_arn = APP_CONFIG[:glacier_sns_arn]
glacier_sqs_queue_name = APP_CONFIG[:glacier_sqs_queue_name]


#Amazon DynamoDB
AWS.config({
    :access_key_id => aws_access_key_id,
    :secret_access_key => aws_secret_access_key,
    :dynamo_db_endpoint => "dynamodb.#{aws_region}.amazonaws.com",
    :sns_endpoint => "sns.#{aws_region}.amazonaws.com",
    :sqs_endpoint => "sqs.#{aws_region}.amazonaws.com",
    :max_retries => 2,
})

puts "Configuring SNS"
sns = AWS::SNS.new

puts "Configuring SQS"
sqs = AWS::SQS.new

# create a table 
puts "Configuring Dynamodb"
dynamo_db = AWS::DynamoDB.new

# make sure table is available
table = dynamo_db.tables[target_dynamo_db]
begin
    if table.status == :active
        puts "#{target_dynamo_db} ready"
    end
rescue
    puts "Creating #{target_dynamo_db}"
    table = dynamo_db.tables.create(target_dynamo_db, 1, 1, { :hash_key => {:vault => :string}, :range_key => {:archive_id => :string} })
    sleep 1 while table.status == :creating
    table.status #=> :active
    puts "Creation of  #{target_dynamo_db} complete"
end

# get a table by name and specify its schema
table = dynamo_db.tables[target_dynamo_db]
table.hash_key = [:vault, :string]
table.range_key = [:archive_id, :string]




# Connect to Glacier
puts "Configuring Glacier"
attributes = { :aws_access_key_id => aws_access_key_id, 
               :aws_secret_access_key => aws_secret_access_key,
               :region => aws_region
        }
glacier = Fog::AWS::Glacier.new(attributes)
vault = glacier.vaults.get(glacier_vault)

## Upload item to glacier
puts "Uploading to Glacier"
archive = vault.archives.create :body => File.new(somefile), :multipart_chunk_size => glacier_multipart_chunk_size, :description => somedescription


## Log item to DynamoDB
puts "Log to Dynamodb"
item = table.items.create('vault' => glacier_vault, 'archive_id' => archive.id)
item.attributes.set 'created_at' => Time.now.to_s
item.attributes.set 'updated_at' => Time.now.to_s
item.attributes.set 'original_file' => somefile
item.attributes.set 'description' => somedescription

# Debug
# puts item.attributes.to_h

puts "Finished Log to Dynamodb"


# Restoration
# Find archive
# table.items.where(:description =>"test1").each {|i| puts i.attributes.to_h}


# Find job if necessary
# File.open(restore_target, "w") {|f| vault.jobs[0].get_output(:io => f) }


# Request archive restore
# job = restore_archive(archive.id)
def restore_archive(vault, archive_id, glacier_sns_arn)
    job = vault.jobs.create(:type => Fog::AWS::Glacier::Job::ARCHIVE, 
                :description => "#{Time.now} Restore Request", 
                :archive_id => archive_id,
                :sns_topic => glacier_sns_arn)
    # Monitor SQS for job ready
end

# Request archive inventory
def get_inventory(vault, glacier_sns_arn)
    job = vault.jobs.create(:type => Fog::AWS::Glacier::Job::INVENTORY, 
                :format => "JSON", 
                :description => "#{Time.now} Inventory Request", 
                :sns_topic => glacier_sns_arn)
    # Monitor SQS for job ready
end


# Give an fog glacier job, restore the file to restore_target
def download_archive(job, restore_target)

    # Prefer to reuse job object from the restore request 
    until job.status_code == "Succeeded"  do
        puts "Sleeping"
        sleep 300
        puts "Checking on job @ #{Time.now} / #{job.id} / #{job.description}"
        job.reload
    end
    File.open(restore_target, "w") {|f| job.get_output(:io => f) }

end




# See if all SNS subscriptions are confirmed
def debug_sns(sns, glacier_sns_arn)
    topic = sns.topics[glacier_sns_arn]
    topic.subscriptions.each do |s| 
        puts s.endpoint
        puts "Confirmed" if s.confirmation_authenticated?
    end
end

# Wait for SQS Message (Caution, polls often and eats up SQS credits)
def poll_for_sqs_message(sqs, glacier_sqs_queue_name)
    queue = sqs.queues.named(glacier_sqs_queue_name)
    queue.poll do |msg|
      puts "Got message: #{msg.body}"
      return msg
    end
end

# Poll for one SQS Message and restore the archive
def poll_and_restore_via_sqs(vault, sqs, glacier_sqs_queue_name)
    # get message
    message = poll_for_sqs_message(sqs, glacier_sqs_queue_name)

    # process
    process_sqs_message(vault, message) unless message.nil?
end



# Get one current SQS Message and restore the archive
def restore_one_sqs_message(vault, sqs, glacier_sqs_queue_name)
    queue = sqs.queues.named(glacier_sqs_queue_name)
    message = queue.receive_message
    process_sqs_message(vault, message) unless message.nil?
end

# Process SQS Message in prep to restore job 
def process_sqs_message(vault, message)
      puts "Process SQS Message: #{message.body}"
      jobid = job_id_from_sqs_message(message)
      unless jobid.nil?
        puts "Restore job_id: #{jobid}"
        restore_target = Time.now.strftime("%Y%m%d.restore")
        restore_archive_from_jobid(vault, jobid, restore_target)
      end
end


# Give an SQS Message (from Glacier -> SNS -> SQS) Figure out the jobID
def job_id_from_sqs_message(message)
    bodyvars = JSON.parse(message.body)
    if bodyvars["Type"] == "Notification"
        messagevars = JSON.parse(bodyvars["Message"])
        if (messagevars["Action"] == "ArchiveRetrieval" || messagevars["Action"] == "InventoryRetrieval") && messagevars["StatusCode"] == "Succeeded"
            jobid = messagevars["JobId"]
            puts "Found Job ID: #{jobid}"
            return jobid
        else
            puts "Not a message of interest"
        end
    else
        puts "Not a notification"
    end
    return nil
end

# Given a vault & jobid, restore to a file named restore_target
def restore_archive_from_jobid(vault, jobid, restore_target)
    job = vault.jobs.get(jobid)
    download_archive(job, restore_target)
end


# Grant permissions so that SNS can post to SQS
def allow_sns_to_sqs(topic, queue)
  policy = AWS::SQS::Policy.new do |policy|
    policy.allow(:actions => ['SQS:*'],
                 :resources => queue.arn,
                 :principals => :any,
                 :conditions => {"StringEquals" => {"aws:SourceArn"=>topic.arn}}
    )
  end
  queue.policy = policy
end

