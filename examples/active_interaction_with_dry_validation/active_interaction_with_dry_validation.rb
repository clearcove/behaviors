# ActiveInteractionWithDryValidation let's you use dry-validation to validate inputs to ActiveInteractions.
#
# Use like so:
#
#     class MyInteraction < ApplicationInteraction
#
#       include ActiveInteractionWithDryValidation
#
#       # Use an external contract, shared with other interactions:
#       class ArgsContract < MyContract
#       end
#
#       # OR
#
#       # Provide a custom contract, just for this interaction:
#       class ArgsContract < ApplicationContract
#
#         SCHEMA = Dry::Schema.Params do
#           # Must provide either issue_attributes or issue_id!
#           optional(:issue_attributes).hash do
#             optional(:issue_data).hash.default({})
#             optional(:assignee_id).string , default: nil
#             optional(:description).string , default: nil
#             optional(:target_workflow_step_id).string , default: nil
#             string :issue_type_class
#             string :reporter_id
#             string :target_workflow_step_id, default: nil
#             string :title
#           end
#         end
#         params(SCHEMA)
#
#         rule()...
#       end
#
#       def execute
#         # Access inputs under #args, e.g., `args.id`
#       end
#
#     end
#
# NOTE: I tried to implement default values via a call_back (see below), however that cause more trouble than it
# was worth when used in nested schemas.
# This macro let's you assign default values to entries in a dry-schema SCHEMA specification, like so:
#     schema = Dry::Schema.Params do
#       optional(:op_type).filled(:string).default('read')
#     end
# See this dry-schema issue (comment): https://github.com/dry-rb/dry-schema/issues/70#issuecomment-598125390
#     class Dry::Schema::Macros::DSL
#        def default(value)
#          schema_dsl.before(:rule_applier) do |result|
#            result.update(name => value) unless result[name]
#          end
#        end
#     end

# Combines ActiveInteraction and dry-validation.
module ActiveInteractionWithDryValidation

  extend ActiveSupport::Concern

  # Represents the inputs provided to the interaction after they were validated by dry-validation.
  class Args

    # @param args [Hash] (@see ArgsContract in calling Interaction)
    # @param args_contract_class [Class] the contract class
    def initialize(args, args_contract_class)
      @args = args.deep_symbolize_keys
      @args_contract_class = args_contract_class
      # Create attr_accessor for each top level schema key and assign the value
      @args_contract_class.schema.key_map.each { |key|
        self.class.class_eval { attr_accessor key.name }
        send("#{key.name}=", @args[key.name.to_sym])
      }
    end

    def to_h
      @args
    end

    def validate
      @args_contract_class.new.call(@args)
    end

  end

  included do
    # Use ActiveInteraction type casting to convert `inputs` into `args`.
    object :args, class: Args, converter: ->(args) { Args.new(args, self::ArgsContract) }
    # Validate args using dry-validation
    validate :validate_args
  end

  def validate_args
    r = args.validate
    return true if r.success?

    # Convert dry-validation errors to ActiveInteraction/ActiveModel ones:
    # * Convert `nil` keys to `:base`. dry-validation uses `nil`, whereas ActiveInteraction expects `:base`
    # * Flatten nested error keys:
    #   { issue_args: { title: ["is missing"]}} => { issue_args_title: ["is missing"] }
    # * Add an error for each message under a given key.
    compatible_errors = {}
    r.errors.to_h.each { |k, messages_or_hash|
      effective_key = k || :base
      extract_nested_messages(compatible_errors, [effective_key], messages_or_hash)
    }
    compatible_errors.each { |error_key, messages|
      messages.each { |message| errors.add(error_key, message) }
    }
  end

  # @param messages_collector [Hash] will be mutated in place with new messages as we find them
  # @param key_stack [Array<String, Symbol>] the stack of keys we are processing
  # @param value [Array, Hash] if it's an Array, extract messages. If it's a hash, process recursively
  def extract_nested_messages(messages_collector, key_stack, value)
    case value
    when Hash
      # Recursively process
      value.each { |k, v| extract_nested_messages(messages_collector, key_stack << k, v) }
    when Array
      # Add value as message to current key_stack
      effective_key = key_stack.map(&:to_s).join("_").to_sym
      messages_collector[effective_key] ||= []
      messages_collector[effective_key].concat(value)
    else
      raise "Handle this: #{key_stack.inspect}, #{value.inspect}"
    end
  end

end
