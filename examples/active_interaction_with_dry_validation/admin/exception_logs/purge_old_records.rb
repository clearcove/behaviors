module Admin
  module ExceptionLogs
    # Purges all ExceptionLogs older than 6 months
    class PurgeOldRecords < ApplicationInteraction

      # @return [true]
      def execute
        ExceptionLog.to_be_purged.delete_all
      end

    end
  end
end
