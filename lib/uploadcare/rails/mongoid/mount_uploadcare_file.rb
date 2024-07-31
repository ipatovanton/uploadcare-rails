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
          cdn_url = send(attribute).to_s
          return if cdn_url.empty?

          uuid = IdExtractor.call(cdn_url)
          cache_key = Uploadcare::Rails::File.build_cache_key(cdn_url)
          default_attributes = { cdn_url: cdn_url, uuid: uuid.presence }
          file_attributes = ::Rails.cache.read(cache_key).presence || default_attributes
          Uploadcare::Rails::File.new(file_attributes)
        end

        class_methods do
          def mount_uploadcare_file(attribute)
            define_method attribute do
              build_uploadcare_file(attribute)
            end

            define_method "uploadcare_store_#{attribute}!" do |store_job = StoreFileJob|
              file_uuid = public_send(attribute)&.uuid
              return unless file_uuid

              if Uploadcare::Rails.configuration.store_files_async
                store_job.perform_later(file_uuid)
              else
                Uploadcare::FileApi.store_file(file_uuid)
              end
            end

            define_method "uploadcare_delete_#{attribute}!" do |delete_job = DeleteFileJob|
              file_uuid = public_send(attribute)&.uuid
              return unless file_uuid

              if Uploadcare::Rails.configuration.delete_files_async
                delete_job.perform_later(file_uuid)
              else
                Uploadcare::FileApi.delete_file(file_uuid)
              end
            end

            unless Uploadcare::Rails.configuration.do_not_store
              after_save do
                if will_save_change_to_attribute?(attribute)
                  send("uploadcare_store_#{attribute}!")
                end
              end
            end

            if Uploadcare::Rails.configuration.delete_files_after_destroy
              after_destroy do
                send("uploadcare_delete_#{attribute}!")
              end
            end
          end
        end
      end
    end
  end
end

Mongoid::Document.include Uploadcare::Rails::Mongoid::MountUploadcareFile
