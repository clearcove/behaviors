class ApplicationInteraction < ActiveInteraction::Base

  # Halt execution on error --- Start
  # https://github.com/antulik/active_interaction-extras/blob/master/lib/active_interaction/extras/halt.rb
  set_callback :execute, :around, ->(_interaction, block) {
    catch :strict_error do
      block.call
    end
  }

  def halt!
    throw :strict_error, errors
  end

  def halt_if_errors!
    halt! if errors.any?
  end
  # Halt execution on error --- End

  # Debug printout --- Start
  def debug(txt)
    puts txt
  end
  # Debug printout --- End

end
