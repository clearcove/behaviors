module Admin
  module RoleAssignments
    # Creates a Role Assignment, effectively assigning a role to a user.
    class Create < ActiveInteraction::Base

      include ActiveInteractionMixin

      string :assigner_id
      string :role_id
      string :scope_id, default: nil
      string :scope_type, default: nil
      string :user_id

      # @return [RoleAssignment]
      def execute
        role = Role.find(role_id)
        user = User.find(user_id)
        assigner = User.find(assigner_id)
        scope = nil
        case role.scope_type
        when "RtUiApp"
          # Nothing to add
        when "Language"
          scope = Language.find_by(id: scope_id)
        else
          raise "Handle this: #{inputs.inspect}"
        end
        if (existing_role_assignment = user.role_assignments.with_state(:active).find_by(role: role, scope: scope))
          return existing_role_assignment
        end

        role_assignment_attrs = {
          role: role,
          started_at: Time.zone.now,
          assigner: assigner,
        }
        case role.scope_type
        when "RtUiApp"
          # Nothing to do
        when "Language"
          if scope.is_a?(Language)
            role_assignment_attrs[:scope] = scope
          elsif scope.nil?
            errors.add(:base, "The role you selected requires a Language selection.")
          else
            errors.add(:scope, "Invalid language scope: #{inputs.inspect}")
          end
        else
          errors.add(:base, "Handle this role: #{role.inspect}")
        end
        if errors.empty?
          ra = user.role_assignments.build(role_assignment_attrs)
          errors.merge!(ra.errors) unless ra.save
        end
        ra
      end

      def to_model
        ::RoleAssignment.new
      end

    end
  end
end
