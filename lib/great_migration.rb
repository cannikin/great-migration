require 'fog'

class GreatMigration

  attr_reader :per_page, :rackspace, :aws, :rackspace_directory, :aws_directory, :files, :total

  def initialize(options={})
    options = default_options.merge(options)
    @per_page = options[:per_page]
    @check_duplicates = options[:aws_check_duplicates]
    @rackspace = Fog::Storage.new({
      :provider           => 'Rackspace',
      :rackspace_username => options[:rackspace_user],
      :rackspace_api_key  => options[:rackspace_key],
      :rackspace_region   => options[:rackspace_region]
    })
    @aws = Fog::Storage.new({
      :provider => 'aws',
      :aws_access_key_id => options[:aws_key],
      :aws_secret_access_key => options[:aws_secret]
    })
    @rackspace_directory = rackspace.directories.get(options[:rackspace_container])
    @aws_directory = aws.directories.get(options[:aws_bucket])
    @aws_keys = @aws_directory.files.map(&:key) if @check_duplicates
    @files = []
    @total = 0
  end

  def default_options
    { :per_page => 10000, aws_check_duplicates: false }
  end

  def copy
    time = Time.now
    pages = rackspace_directory.count / per_page + 1
    marker = ''

    # get Rackspace files
    pages.times do |i|
      puts "! Getting page #{i+1}..."
      files = rackspace_directory.files.all(:limit => per_page, :marker => marker).to_a
      puts "! #{files.size} files in page #{i+1}, forking..."
      pid = fork do
        copy_files(i, files)
      end
      puts "! Process #{pid} forked to copy files"
      marker = files.last.key
      @total += files.size
    end

    pages.times do
      Process.wait
    end

    puts "--------------------------------------------------"
    puts "! #{total} files copied in #{Time.now - time}secs."
    puts "--------------------------------------------------\n\n"
  end

  private def copy_files(page, files)
    puts "  [#{Process.pid}] Page #{page+1}: Copying #{files.size} files..."
    total = files.size
    max_processes = 8
    process_pids = {}
    time = Time.now

    while !files.empty? or !process_pids.empty?
      while process_pids.size < max_processes and files.any? do
        file = files.pop
        pid = Process.fork do
          copy_file(page, file)
        end
        process_pids[pid] = { :file => file }
      end

      if pid_done = Process.wait
        if job_finished = process_pids.delete(pid_done)
          puts "    [#{Process.pid}] Page #{page+1}: Finished #{job_finished[:file].key}."
        end
      end
    end

    puts "  [#{Process.pid}] ** Page #{page+1}: Copied #{total} files in #{Time.now - time}secs"
  end

  private def copy_file(page, file)
    if file.content_type == 'application/directory'
      # skip directories
    else
      if @check_duplicates and @aws_keys.include?(file.key)
        puts "    [#{Process.pid}] ** Page #{page+1}: File already exists skipping... #{file.key}"
      else
        aws_directory.files.create(
          :key          => file.key,
          :body         => file.body,
          :content_type => file.content_type,
          :public       => true)
      end
    end
  end

end
