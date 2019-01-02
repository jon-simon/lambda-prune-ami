#!/usr/bin/env ruby

require 'aws-sdk-ec2'
require 'logger'

## Simple class to make adding log messages easy
class SimpleLog
  ## Example SimpleLog.log.<level> "log message"
  def self.log
    if @logger.nil?
      @logger = Logger.new STDOUT
      ## Example of sending log to a file instead of stdout
      # @logger = Logger.new 'path/to/log/files/log.txt'
      @logger.level = Logger::INFO
      @logger.datetime_format = '%Y-%m-%d %H:%M:%S '
    end
    @logger
  end
end

## Class for managing AMIs.  Only method is pruning for now.
class AMIManage
  ### Initialize the the class with region, owner, retain, filter values,

  def initialize(region, owner, retain, filter)
    @region = region # AWS region
    @client = Aws::EC2::Client.new(region: @region)
    @owner = owner # AMI Owner ID,
    @retain = retain.to_i # Number of AMI copies to retain
    @filter = filter
  end

  def prune
    amis = @client.describe_images(
      owners: [@owner],
      filters: [
        {
          name: 'state',
          values: %w[available invalid transient failed error]
        },
        {
          name: 'name',
          values: ["#{@filter}*"]
        }
      ]
    )
    if amis.images.count - @retain > 0
      sorted_amis = amis.images.sort_by(&:creation_date)
      sorted_amis[0..((amis.images.count - @retain) - 1).to_i].each do |ami|
        SimpleLog.log.info "Deregistering #{ami.image_id}"
        @client.deregister_image(image_id: ami.image_id)
      end
    else
      SimpleLog.log.info 'Total number of AMIs is below retention threshold.'
    end
  end
end

## lambda_handler will be the entrypoint for the lambda trigger event
def lambda_handler(*)
  ENV['AWS_AMI_REGIONS'].split(',').each do |region|
    image = AMIManage.new(
      region.strip,
      ENV['OWNER_ACCT_ID'],
      ENV['COPIES_TO_RETAIN'],
      ENV['AMI_FILTER']
    )
    image.prune
  end
end
