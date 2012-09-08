## icypop

* Uploads a file of choice to Amazon Glacier with a description
* Logs the file upload to Amazon DynamoDB so it's easy to find the ArchiveID without requesting an inventory
    * (Because inventories can take a day to produce)


## Wishlist

* Easy way to request a download

## Usage

ruby ./icypop file.name "description of file"


## Configuration

Create a file named icypop.yml

It should contain the following:

    production:
        :aws_access_key_id: ""
        :aws_secret_access_key: ""  
        :aws_region: ""
        :glacier_vault: ""
        :glacier_multipart_chunk_size: 1048576
        :target_dynamo_db: "glacier_upload_log"


* aws_access_key_id: Your AWS Access Key
* aws_secret_access_key: Your AWS Secret Key
* aws_region: Whatever region you're using (Used for both Glacier and DynamoDB)
* glacier_vault: Name of the glacier vault you want to upload to
* glacier_multipart_chunk_size: Upload Chunksize when sending to Glacier
* target_dynamo_db: Name of DynamoDB you want to upload to



## Contributing

* Find something you would like to work on. For suggestions look for the `easy`, `medium` and `hard` tags in the [issues](https://github.com/pctj101/icypop/issues)
* Fork the project and do your work in a topic branch.
* Rebase your branch against fog/fog to make sure everything is up to date.
* Commit your changes and send a pull request.

## Additional Resources

## Sponsorship

## Copyright

(The MIT License)

Copyright (c) 2010 [geemus (Wesley Beary)](http://github.com/geemus)

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
