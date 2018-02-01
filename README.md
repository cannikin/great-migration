# Great Migration

Ever have to migrate from Rackspace Files to S3? I did. And I couldn't find a simple way to do it, so I made one. There's a service [mover.io](https://mover.io/) but it gave up after 25,000 objects. I had to copy 175,000.

This is a Ruby script which will log into Rackspace, get a list of all objects from a container (paged in groups of 10,000 by default), and copy those objects to an S3 bucket.

## Usage

Install require gems:

    bundle install

Call `bin/greatmigration` and pass the required options:

    bin/greatmigration --rackspace-user=username --rackspace-key=123456 \
      --rackspace-container=rackcontainername --rackspace-region=rackspaceregion_like_ord --aws-key=ABCDEF \
      --aws-secret=987654 --aws-bucket=s3bucketname \
      --aws-region=awsregion_like_us-west-2

Check out `bin/greatmigration -h` for a couple more optional parameters.

## Technical Description

To get as much performance out of this script as possible it forks processes to do the actual copying of files to avoid the GIL which is still in place with threads. The first fork occurs after grabbing a page of results from Rackspace. That fork will take care of copying all of the objects in that page. Then we pull from a pool of 8 processes to actually do the uploading of individual objects.

    bin/greatmigration
    |
    +-- page process
    |   |
    |   +-- upload process
    |   +-- upload process
    |
    |-- page process
    |   |
    |   +-- upload process
    |   +-- upload process
    |
    |-- ...
    
In my usage I ended up forking 18 "page" processes and typically had 4-6 "upload" processes running under each one simultaneously. If you have millions of objects you may want to tweak the code to actually start the page processes from a pool as well (otherwise you could end up with a very large number of processes, one for every block of 10,000 objects).

## Performance

Your results may vary, but I ran this script on a c4.4xlarge EC2 instance (16 cores). This maxed out the CPUs for the entire run and copied 174,754 objects in 5,430 seconds (just over an hour and a half). This ended up costing $1.32.
