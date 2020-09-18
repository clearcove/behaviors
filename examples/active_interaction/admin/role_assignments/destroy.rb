module Admin
  module RoleAssignments
    # Destroys a Role Assignment, effectively revoking a role from a user.
    class Destroy < ActiveInteraction::Base

      include ActiveInteractionMixin

      string :id

      # @return [RoleAssignment]
      def execute
        role_assignment = RoleAssignment.find(id)
        role_assignment.ended_at = Time.zone.now
        role_assignment.deactivate!
        role_assignment
      end

    end
  end
end
