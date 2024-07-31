# frozen_string_literal: true

require 'mongoid'
require 'active_support/concern'
require 'uploadcare/rails/services/id_extractor'
require 'uploadcare/rails/jobs/delete_file_job'
require 'uploadcare/rails/jobs/store_file_job'

module Uploadcare
  module Rails
    module Mongoid
      module MountUploadcareFile
        extend ActiveSupport::Concern

        def build_uploadcare_file(attribute)
          cdn_url = attributes[attribute.to_s].to_s
          return if cdn_url.empty?

          uuid = IdExtractor.call(cdn_url)
          cache_key = File.build_cache_key(cdn_url)
          default_attributes = { cdn_url: cdn_url, uuid: uuid.presence }
          file_attributes = ::Rails.cache.read(cache_key).presence || default_attributes
          Uploadcare::Rails::File.new(file_attributes)
        end

        class_methods do
          def mount_uploadcare_file(attribute)
            define_method attribute do
              build_uploadcare_file attribute
            end

            define_method "uploadcare_store_#{attribute}!" do |store_job = StoreFileJob|
              file_uuid = public_send(attribute)&.uuid
              return unless file_uuid
              return store_job.perform_later(file_uuid) if Uploadcare::Rails.configuration.store_files_async

              Uploadcare::FileApi.store_file(file_uuid)
            end

            define_method "uploadcare_delete_#{attribute}!" do |delete_job = DeleteFileJob|
              file_uuid = public_send(attribute)&.uuid
              return unless file_uuid
              return delete_job.perform_later(file_uuid) if Uploadcare::Rails.configuration.delete_files_async

              Uploadcare::FileApi.delete_file(file_uuid)
            end

            unless Uploadcare::Rails.configuration.do_not_store
              after_save :"uploadcare_store_#{attribute}!", if: proc { |record| record.attribute_will_change?(attribute) }
            end

            return unless Uploadcare::Rails.configuration.delete_files_after_destroy

            after_destroy :"uploadcare_delete_#{attribute}!"
          end
        end
      end
    end
  end
end

Mongoid::Document.include Uploadcare::Rails::Mongoid::MountUploadcareFile
