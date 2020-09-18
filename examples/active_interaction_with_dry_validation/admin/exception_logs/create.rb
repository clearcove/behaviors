module Admin
  module ExceptionLogs
    # Creates an Exception Log and sends an email notification
    class Create < ApplicationInteraction

      include ActiveInteractionWithDryValidation

      # Contract for validating args
      class ArgsContract < ApplicationContract

        SCHEMA = Dry::Schema.Params do
          # NOTE: We don't require any attrs or values to make sure that writing an
          # ExceptionLog doesn't fail because of invalid input args, thus never becoming visible
          # in the logs, and never getting noticed.
          optional(:actor_id).maybe(:str?)
          optional(:actor_name).maybe(:str?)
          optional(:backtrace).maybe(:str?)
          optional(:description).maybe(:str?)
          optional(:error_class).maybe(:str?)
          optional(:ip_address).maybe(:str?)
          optional(:request_params).maybe(:hash?)
        end

        params(SCHEMA)

      end

      EXCEPTION_CLASSES_WITH_NO_EMAIL = [
        "RtUi::Error::ForbiddenRequest",
        "Pundit::NotAuthorizedError",
      ].freeze

      # @return [ExceptionLog] the newly created ExceptionLog
      def execute
        # Create exception_log
        exception_log = ExceptionLog.new(args.to_h)
        errors.merge!(exception_log.errors) unless exception_log.save
        return exception_log if EXCEPTION_CLASSES_WITH_NO_EMAIL.include?(exception_log.error_class)

        # Send email to developers
        app_url = Rails
                    .application
                    .routes
                    .url_helpers
                    .admin_exception_log_url(id: exception_log.id, host: ENV["SERVER_HOST"])
        notification_body_text = [
          "Error class: #{exception_log.display_error_class}",
          "Actor: #{exception_log.display_actor_name}",
          "Message: #{exception_log.display_description}",
          "View in : #{app_url}",
          "Params: #{exception_log.request_params.inspect}",
          "Backtrace:",
          exception_log.backtrace,
        ].join("\n\n")
        ::Infrastructure::AwsSes::SendEmailWorker.perform_async(
          args: {
            body_text: notification_body_text,
            recipients: DEVELOPER_EMAILS,
            subject: "[RtUi] Exception: #{exception_log.display_error_class}",
          },
        )

        exception_log
      end

      def to_model
        ExceptionLog.new
      end

    end
  end
end
