defmodule Edenflowers.Feedback.Note do
  @moduledoc """
  A reviewer's comment on one element of a page, with enough of the element's
  context (selector, text, HTML and, in dev, its HEEx source) to find it again.
  """

  use Ash.Resource,
    domain: Edenflowers.Feedback,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "feedback_notes"
    repo Edenflowers.Repo
  end

  actions do
    defaults [:read]

    create :leave do
      description "A reviewer leaves a note on the element they Option+Clicked. The app version is recorded so " <>
                    "you can tell whether a later release already fixed it."

      accept [:body, :path, :locale, :viewport, :selector, :element_text, :element_html, :source]
      # Without an actor the policy, not this change, turns the request away.
      change relate_actor(:author, allow_nil?: true)
      change set_attribute(:app_version, &__MODULE__.app_version/0)
    end

    read :open do
      description "Notes nobody has resolved yet, oldest first, for `just review-comments`."
      filter expr(is_nil(resolved_at))
      prepare build(sort: [inserted_at: :asc])
    end

    update :resolve do
      description "Marks a note as dealt with, so it drops out of `open`."
      change set_attribute(:resolved_at, &DateTime.utc_now/0)
    end
  end

  # Admins pass the bypass, so reviewers plus admins can leave notes: the same
  # people `User.can_review?` shows the picker to.
  policies do
    bypass actor_attribute_equals(:system, true) do
      authorize_if always()
    end

    bypass actor_attribute_equals(:admin, true) do
      authorize_if always()
    end

    policy action(:leave) do
      authorize_if actor_attribute_equals(:reviewer, true)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :body, :string do
      description "What the reviewer wrote."
      allow_nil? false
    end

    attribute :path, :string do
      description "The page's path and query string, e.g. /sv/store?sort=price."
      allow_nil? false
      constraints max_length: 2000
    end

    attribute :locale, :string do
      description "The page's language, from its <html lang>."
    end

    attribute :viewport, :string do
      description "The browser window's size as WIDTHxHEIGHT, since many notes are about layout."
    end

    attribute :selector, :string do
      description "A CSS selector path to the element, from the nearest id down. Brittle across releases, " <>
                    "so read it with `element_text` and `element_html`."

      allow_nil? false
      constraints max_length: 2000
    end

    attribute :element_text, :string do
      description "The element's visible text, cut to 500 characters by the picker."
      constraints max_length: 500
    end

    attribute :element_html, :string do
      description "The element's outerHTML, cut to 2000 characters by the picker."
      constraints max_length: 2000
    end

    attribute :source, :string do
      description "The HEEx file:line that rendered the element. Only dev has the annotations, so production notes " <>
                    "have none."
    end

    attribute :app_version, :string do
      description "The release the reviewer was looking at, e.g. v1.14.4."
      allow_nil? false
    end

    attribute :resolved_at, :utc_datetime do
      description "When the note was dealt with. Nil while it is open."
    end

    timestamps()
  end

  relationships do
    belongs_to :author, Edenflowers.Accounts.User do
      description "The reviewer who left the note."
      allow_nil? false
    end
  end

  def app_version, do: "v#{Application.spec(:edenflowers, :vsn)}"
end
