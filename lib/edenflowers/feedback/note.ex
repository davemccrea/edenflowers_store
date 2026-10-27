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

      accept [:body, :path, :locale, :viewport, :selector, :element_text, :element_html, :source, :strings]
      # Without an actor the policy, not this change, turns the request away.
      change relate_actor(:author, allow_nil?: true)
      change set_attribute(:app_version, &__MODULE__.app_version/0)
    end

    read :open do
      description "Notes nobody has resolved yet, oldest first, for `just review-comments`."
      filter expr(is_nil(resolved_at))
      prepare build(sort: [inserted_at: :asc])
    end

    read :open_on_page do
      description "Open notes left on one page (path and query string), so the picker can mark their elements " <>
                    "while a reviewer holds Option."

      argument :path, :string do
        description "The page's path and query string, matched exactly as `leave` stored it."
        allow_nil? false
      end

      filter expr(is_nil(resolved_at) and path == ^arg(:path))
      prepare build(sort: [inserted_at: :asc], load: [:mine?])
    end

    action :find_strings, {:array, :map} do
      description "The Gettext messages whose rendered text equals one of `texts` in `locale`, each with its " <>
                    "domain, msgctxt, msgid and its text in every locale, for the note box. A reverse lookup " <>
                    "in `priv/gettext`, see `Edenflowers.Feedback.Catalogue`."

      argument :texts, {:array, :string} do
        description "The clicked element's visible text, its text nodes and attributes such as placeholder and alt."
        allow_nil? false
        constraints max_length: 50
      end

      argument :locale, :string do
        description "The page's language, from its <html lang>."
        allow_nil? false
      end

      run fn input, _context ->
        {:ok, Edenflowers.Feedback.Catalogue.matches(input.arguments.texts, input.arguments.locale)}
      end
    end

    update :edit do
      description "The reviewer rewrites their note after Option+Clicking the same element again."
      accept [:body]
    end

    destroy :delete do
      description "The reviewer takes back their own note, from the box that opens when they Option+Click its " <>
                    "element again. Unlike `resolve`, it leaves no trace, for notes left by mistake."
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

    policy action([:read, :leave, :open_on_page, :find_strings]) do
      authorize_if actor_attribute_equals(:reviewer, true)
    end

    policy action([:edit, :delete]) do
      authorize_if relates_to_actor_via(:author)
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

    attribute :strings, {:array, :map} do
      description "The Gettext messages the element seemed to render when the note was left, as " <>
                    "`find_strings` returned them: domain, msgctxt, msgid and their text in every locale. " <>
                    "Empty for text from the database."

      default []
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

  calculations do
    calculate :mine?, :boolean, expr(author_id == ^actor(:id)) do
      description "Whether the actor wrote the note, so Option+Clicking its element opens it for editing."
    end
  end

  def app_version, do: "v#{Application.spec(:edenflowers, :vsn)}"
end
