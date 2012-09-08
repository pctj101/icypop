#!/usr/bin/ruby

puts "Starting Dynolog"

# require your gems as usual
require "rubygems"
require "bundler/setup"
require "fog"
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

puts "Reading Environment for Dynolog"

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

#Amazon DynamoDB
puts "Configuring Dynamodb"
AWS.config({
    :access_key_id => aws_access_key_id,
    :secret_access_key => aws_secret_access_key,
    :dynamo_db_endpoint => "dynamodb.#{aws_region}.amazonaws.com",
    :max_retries => 2,
})


# create a table 
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
require 'fog/aws/glacier'
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
