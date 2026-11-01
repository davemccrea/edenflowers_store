defmodule Edenflowers.Catalog.FormerProductSlug do
  @moduledoc """
  A slug a product used to have. Links shared with it redirect to the
  product's current slug, and no other product can take it, so an old link
  never quietly opens a different product.
  """

  use Ash.Resource,
    otp_app: :edenflowers,
    domain: Edenflowers.Catalog,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "former_product_slugs"
    repo Edenflowers.Repo

    references do
      reference :product, on_delete: :delete
    end
  end

  actions do
    defaults [:read]

    create :create do
      description "Remembers `slug` as one `product_id` used to have. Product's `update` writes it when " <>
                    "Jennie changes a slug."

      accept [:slug, :product_id]
    end

    destroy :destroy do
      description "Forgets a former slug, when its own product takes it back as its current slug."
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
    belongs_to :product, Edenflowers.Catalog.Product do
      description "The product links with this slug now redirect to."
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_slug, [:slug]
  end
end
