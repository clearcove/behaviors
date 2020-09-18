# Behaviors

This repo explores solutions for implementing behaviors in Rails applications.

* Naming
* Overview
* Requirements
* Code examples
* Conventions
* Prior art

## Naming

This is a tricky one. Here are some options in order of preference:

* Services - Very common term for this concept, well understood.
* Behaviors - The B-part in `Data vs. Behavior`
* Interactions - Not all of these will be (user) interactions!
* Mutations - Not all of these will be (ActiveRecord) mutations!
* Processes
* Jobs
* Commands
* Tasks

## Overview

**Disclaimer**: The below assumes "Interactions" as name and "ActiveInteraction" for implementation. That is not necessarily true for the final implementation!

* They are organized by contexts/workspacesjust like controllers and views. And their names start with a verb. Examples:
    * admin/users/create.rb
    * infrastructure/dns/check_host_resolution.rb
    * authentication/via_password.rb
    * project_management/workflows/clone.rb
* They have a single, consistently named, public class method to invoke them. Examples: `Service.call` or `Service.run`. NOTE: There may also be a bang version of this method, e.g., `#run!`.
* They receive the same arguments as the corresponding controller action does (via `params`). That makes it easy to invoke an Interaction from a controller action, from a production console, or in a test.
* All attributes of the wrapped AR model are exposed as direct inputs on the interaction so that the interaction can be used as form object for Rails forms.
* They validate, restrict, and coerce their input args using ActiveInteraction mechanisms. That means we don't need strong params.
* Error handling: Prefer validity over raising exceptions. Use `errors.add` and `errors.merge!`. When passing input arguments and there is a chance that something can go wrong, call `.run` instead of `.run!`. Otherwise calling `.run!` is fine.

## Requirements

### Composition

We want to be able to easily compose behaviors to facilitate re-use and modularity.

* Errors raised in composed behaviors should be merged into the parent behavior.
* Execution in parent behavior should not continue when a composed service fails.
* Composed behaviors act like the `#call!` bang method with exception handling built in.

Code example:

``` ruby
  def call
    r1 = compose(Nested::Service1, arg1: 123, arg2: "a string")
    r2 = compose(Nested::Service2, arg1: r1)
  end
```

### Exception handling and error reporting

* Any exceptions or errors raised in a behavior are accessible to the caller for testing and notification purposes.
* Errors can be added manually inside the behavior via `errors.add(:base, text: "something went wrong", key: :something_went_wrong)`.
* Errors can be merged from other sources, e.g., ActiveRecord objects or nested behaviors via `errors.merge(@user.errors)`.

### Internationalization

Success and error messages can be customized via Rails' default I18n mechanisms (local files).

### Input validation and coercion

All inputs are validated and coerced before the behavior is invoked. See below for more on this topic.

### Output validation

The behavior's return value should also be validated.

### Usable as form object

An instance of the behavior should be usable as a Rails form object for seamless integration with form based processes.

### Dependency injection

Dependencies can be injected into the behavior, mostly for testing. Example: We should be able to inject a fake `Git` library when testing code that makes git commits. Other examples: `File`, `Time`, `TwitterApi`, etc.

## Input validation

Below are some options for input argument validation:

* Sorbet
* dry-validation
* ActiveInteraction filters

## Code examples

### Simple interaction

``` ruby
# app/controllers/admin/users_controller.rb
...

  def update
    outcome = Admin::Users::Update.call(params[:user])
    if outcome.success?
      @user = outcome.result
      redirect_to admin_user_path(@user)
    else
      @user = outcome
      render(:edit)
    end
  end

...
```

``` ruby
# app/services/admin/users/update.rb

module Admin
  module Users
    class Update < ApplicationService

      # Input validation
      params do
        required(:id).filled(:integer)
        required(:first_name).filled(:string)
        required(:last_name).filled(:string)
        required(:email).filled(:string)
        optional(:birth_date).filled(:date)
        optional(:avatar).maybe(:string)
      end

      # @return [User] the updated user
      def call
        # At this point all inputs are validated and we can implement the business logic
        @user = User.find(args.id)
        errors.merge(@user.errors) unless @user.update(args.except(:id))
        @user
      end

    end
  end
```

## Conventions

* They receive the same arguments as the corresponding controller action would expect as `params`. That makes it easy to invoke an Interaction from a controller action: Just forward the params as is. Just basic ruby data types of hashes, arrays, strings, numbers, etc.
    * :id - when an id is required, e.g., to update a record, we wrap it in a hash under key `:non_ar_attrs`: `{ non_ar_attrs: { id: 123 }}` where it can be used to find the record, however it will never be written to the db.
    * model attributes are specified at the top level so that the interaction object responds to the same attributes as the AR model. This allows using the interaction instance as a form object.
* Additional arguments are wrapped under `:non_ar_attrs` hash in inputs to make update and create easy: `inputs.except(:non_ar_attrs)`.
* They inherit from ApplicationInteraction (ActiveInteraction::Base).
* They use the ActiveInteraction gem.
* Validations: Go on the ActiveRecord model by default. Move them to interactions only if they are specific to the interaction.
* For complex input coercion and validation scenarios consider using dry-validation in a `before_type_check` callback.
* Composition: ActiveInteraction has a `#compose` method. TODO: Investigate what advantages it provides over calling nested interactions manually.
* `#to_model`: Add this method to #create (`::Job.new`) and #update (`::Job.find(non_ar_attrs[:id])`) interactions.
* Delegating display methods to underlying object:
    * Use `attr_reader :<wrapped_object>` and `delegate :display_name, to: :<wrapped_object>, prefix: false`
    * This is also useful if the AR model has nested attributes. Then we can delegate those as well to make them available if the interaction is used as a form object and nested attributes need to be accessed.
* Optional inputs and nil: When updating a model's attribute we need to handle the following cases:
    * attr not given, so leave DB column as is (check via attr? predicate)
    * attr given: Update DB column with new value
  It appears that attr? returns true for an empty string (""), so if you e.g., want to check if a state machine trigger event was selected, you have to use `attr.present?` rather than `attr?`.
  ActiveInteraction can handle this via the `#given?` predicate. (https://github.com/AaronLasseigne/active_interaction#optional-inputs)
* When referring to ActiveRecord models in the class name or namespace, use plural form. This is to avoid naming conflicts with ActiveRecord models.
* Rails nested attributes: Require special treatment. See the following classes in rbpa for an example:
    * Pm::WorkflowStepActionsController
    * Pm::WorkflowStepActions::Update
    * UPDATE: Delegation may be a better way to handle this!
* See [ActiveInteraction docs](https://github.com/AaronLasseigne/active_interaction#rails) for how to integrate them into controllers and forms.
* infrastructure
    * We house this under the `interactions` folder so that the "infrastructure" part of the namespace doesn't get lost.
    * Makes underlying technology available to the app. All infrastructure services live in this folder.
    * Organized/grouped from a provider perspective. Services are aligned with underlying technology.
    * These wrap service providers so that if we swap out a service provider we have a single place to change code.
    * Examples:
        * google_places_api.rb
        * facebook_authentication_api.rb
* Example files:
    * pm
        * workflow_steps
            * create.rb

## Prior art

### ActiveInteraction

I have used this library extensively and I like it a lot.

Aspects that could be improved:

* Input validation (it's quite lacking)
* It has features I don't use (e.g., automatic ActiveRecord integration via :id and find)

Further reading:

* Interesting article about [4 use cases for ActiveInteraction](https://www.viget.com/articles/four-uses-for-activeinteraction/)
* [ActiveInteraction-extras](https://github.com/antulik/active_interaction-extras)
* An opposing opinion in this blog post, advising against interactions and using domain objects instead: https://www.codewithjason.com/organizing-rails-projects-domain-objects-good-service-objects-bad/

### Existing AKII solution

We have developed an in-house solution and it is being used in production. However, there are some aspects I'm not a big fan of:

* Permissions don't belong inside behaviors.
* Dependency injection is very cumbersome.

### Hanami interactors

https://guides.hanamirb.org/architecture/interactors/

### CollectiveIdea/Interactor

https://github.com/collectiveidea/interactor

### Gitlab

Gitlab has a concept of services, however they don't seem to have strong conventions: https://gitlab.com/gitlab-org/gitlab-foss/-/blob/master/app/services/repositories/destroy_service.rb

### Rubygems.org

https://github.com/rubygems/rubygems.org/blob/master/app/jobs/delete_user.rb

### OpenProject

https://github.com/opf/openproject/tree/dev/app/services

### Discourse

https://github.com/discourse/discourse/tree/master/app/services

### Cypriss/Mutations

https://github.com/cypriss/mutations

### Other articles

* doers, events, commands, multitools: https://www.morozov.is/2020/06/01/helpful-service-objects-part-1-chosing-right-design.html
* https://www.toptal.com/ruby-on-rails/rails-service-objects-tutorial
* https://hackernoon.com/the-3-tenets-of-service-objects-c936b891b3c2
* https://avdi.codes/service-objects/
* http://brewhouse.io/blog/2014/04/30/gourmet-service-objects.html
