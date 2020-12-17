class S3Helper
  def initialize(access_key:, secret_key:, bucket:, region:)
    @access_key = access_key
    @secret_key = secret_key
    @bucket = bucket
    @region = region
  end

  def download(key, dest)
    Chef::Log.info("Downloading #{key} into #{dest}")

    client.get_object({
      bucket: @bucket,
      key: key,
      response_target: dest,
    })
  end

  def objects_by_prefix(search_prefix)
    client.list_objects_v2({
      bucket: @bucket,
      prefix: search_prefix,
    })
  end

  private

  def client
    require "aws-sdk-s3"

    Aws::S3::Client.new(
      access_key_id: @access_key,
      secret_access_key: @secret_key,
      region: @region
    )
  end
end
