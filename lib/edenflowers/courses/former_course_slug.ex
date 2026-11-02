defmodule Edenflowers.Courses.FormerCourseSlug do
  @moduledoc """
  A slug a course used to have. Links shared with it redirect to the
  course's current slug, and no other course can take it, so an old link
  never quietly opens a different course.
  """

  use Ash.Resource,
    otp_app: :edenflowers,
    domain: Edenflowers.Courses,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "former_course_slugs"
    repo Edenflowers.Repo

    references do
      reference :course, on_delete: :delete
    end
  end

  actions do
    defaults [:read]

    create :create do
      description "Remembers `slug` as one `course_id` used to have. Course's `update` writes it when " <>
                    "Jennie changes a slug."

      accept [:slug, :course_id]
    end

    destroy :destroy do
      description "Forgets a former slug, when its own course takes it back as its current slug."
    end
  end

  policies do
    bypass actor_attribute_equals(:admin, true) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if always()
    end

    policy action_type([:create, :destroy]) do
      forbid_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :slug, :string do
      description "The old slug, as it appeared in links."
      allow_nil? false
      public? true
    end

    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :course, Edenflowers.Courses.Course do
      description "The course links with this slug now redirect to."
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_slug, [:slug]
  end
end
