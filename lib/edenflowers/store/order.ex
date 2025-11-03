defmodule Edenflowers.Store.Order do
  use Ash.Resource,
    domain: Edenflowers.Store,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub]

  use Gettext, backend: EdenflowersWeb.Gettext

  require Ash.Resource.Change.Builtins
  import Edenflowers.Actors

  alias __MODULE__.{
    ValidateAndCalculateFulfillment,
    MaybeRequireDeliveryAddress,
    LookupPromotionCode,
    MaybeRequireRecipientName,
    ClearGiftFields,
    UpsertUserAndAssignToOrder
  }

  postgres do
    repo Edenflowers.Repo
    table "orders"
  end

  code_interface do
    define :create_for_checkout, action: :create_for_checkout
    define :get_by_id, action: :get_by_id, args: [:id]
    define :get_by_order_reference, action: :get_by_order_reference, args: [:order_reference]
    define :get_for_checkout, action: :get_for_checkout, args: [:id]
    define :get_all_completed, action: :get_all_completed
    define :finalise_checkout, action: :finalise_checkout
    define :add_payment_intent_id, action: :add_payment_intent_id, args: [:payment_intent_id]
    define :add_promotion_with_id, action: :add_promotion_with_id, args: [:promotion_id]
    define :add_promotion_with_code, action: :add_promotion_with_code, args: [:code]
    define :clear_promotion, action: :clear_promotion
    define :update_fulfillment_option, action: :update_fulfillment_option, args: [:fulfillment_option_id]
    define :update_gift, action: :update_gift, args: [:gift]
    define :update_locale, action: :update_locale, args: [:locale]
    define :reset, action: :reset
  end

  actions do
    defaults [:create, :read, :update, :destroy]

    # Read Actions
    read :get_by_id do
      argument :id, :uuid, allow_nil?: false
      filter expr(id == ^arg(:id))
      get? true
    end

    read :get_by_order_reference do
      argument :order_reference, :string, allow_nil?: false

      prepare fn query, _context ->
        require Ash.Query
        order_reference = Ash.Query.get_argument(query, :order_reference)

        case Edenflowers.Sqids.decode(order_reference) do
          {:ok, [order_number]} ->
            Ash.Query.filter(query, order_number == ^order_number)

          _ ->
            # Invalid order reference - return query that matches nothing
            Ash.Query.filter(query, false)
        end
      end

      get? true
    end

    read :get_for_checkout do
      argument :id, :uuid, allow_nil?: false
      filter expr(id == ^arg(:id))
      get? true

      prepare build(
                load: [
                  # Aggregates
                  :total_items_in_cart,
                  :discount_amount,
                  :line_total,
                  :line_tax_amount,
                  # Calculations
                  :promotion_applied?,
                  :order_reference,
                  :total,
                  :tax_amount,
                  :fulfillment_tax_amount,
                  # Relationships
                  :promotion,
                  :fulfillment_option,
                  :line_items
                ]
              )
    end

    read :get_all_completed do
      filter expr(state == :order)
    end

    # Create Actions
    create :create_for_checkout do
      change set_attribute(:step, 1)
    end

    # Step-specific Update Actions
    update :edit_step_1 do
      change set_attribute(:step, 1)
    end

    update :save_step_1 do
      accept [:customer_name, :customer_email]
      require_attributes [:customer_name, :customer_email]
      change {UpsertUserAndAssignToOrder, []}
      change set_attribute(:step, 2)
      require_atomic? false
    end

    update :edit_step_2 do
      change set_attribute(:step, 2)
    end

    update :save_step_2 do
      accept [:gift, :recipient_name, :gift_message]
      change set_attribute(:step, 3)
      change {MaybeRequireRecipientName, []}
      change {ClearGiftFields, []}
      require_atomic? false
    end

    update :edit_step_3 do
      change set_attribute(:step, 3)
    end

    update :save_step_3 do
      accept [
        :fulfillment_option_id,
        :recipient_name,
        :recipient_phone_number,
        :delivery_address,
        :delivery_instructions,
        :fulfillment_date,
        :fulfillment_amount,
        :calculated_address,
        :here_id,
        :distance,
        :position
      ]

      require_attributes [:fulfillment_date]
      change {MaybeRequireDeliveryAddress, []}
      change {ValidateAndCalculateFulfillment, []}
      change set_attribute(:step, 4)
      require_atomic? false
    end

    update :save_step_4 do
      accept []
    end

    # Other Update Actions
    update :finalise_checkout do
      change set_attribute(:state, :order)
      change set_attribute(:payment_status, :paid)
      change set_attribute(:ordered_at, &DateTime.utc_now/0)
    end

    update :update_fulfillment_option do
      accept [:fulfillment_option_id]
      # When filfillment_option is updated, clear chosen fulfillment date
      change set_attribute(:fulfillment_date, nil)
    end

    update :update_gift do
      accept [:gift]
    end

    update :update_locale do
      argument :locale, :string, allow_nil?: false
      change atomic_update(:locale, expr(^arg(:locale)))
    end

    update :add_payment_intent_id do
      accept [:payment_intent_id]
    end

    update :add_promotion_with_id do
      argument :promotion_id, :uuid, allow_nil?: false
      change atomic_update(:promotion_id, expr(^arg(:promotion_id)))
    end

    update :add_promotion_with_code do
      argument :code, :string
      change {LookupPromotionCode, []}
      require_atomic? false
    end

    update :clear_promotion do
      # TODO: use atomic_update here?
      change set_attribute(:promotion_id, nil)
    end

    update :reset do
      change set_attribute(:step, 1)
      change set_attribute(:customer_name, nil)
      change set_attribute(:customer_email, nil)
      change set_attribute(:gift, false)
      change set_attribute(:gift_message, nil)
      change set_attribute(:recipient_name, nil)
      change set_attribute(:recipient_phone_number, nil)
      change set_attribute(:delivery_address, nil)
      change set_attribute(:delivery_instructions, nil)
      change set_attribute(:fulfillment_date, nil)
      change set_attribute(:fulfillment_amount, nil)
      change set_attribute(:calculated_address, nil)
      change set_attribute(:here_id, nil)
      change set_attribute(:distance, nil)
      change set_attribute(:position, nil)
      change set_attribute(:payment_intent_id, nil)
      change set_attribute(:promotion_id, nil)
      change set_attribute(:fulfillment_option_id, nil)
    end
  end

  policies do
    # System bypass - for webhooks and background jobs
    bypass actor_attribute_equals(:system, true) do
      authorize_if always()
    end

    # Admin bypass - admins can do anything
    bypass actor_attribute_equals(:admin, true) do
      authorize_if always()
    end

    # Allow creating orders without authentication (for checkout flow)
    policy action_type(:create) do
      authorize_if always()
    end

    # Read/Update access:
    # Multiple authorize_if within one policy = OR (only one needs to pass)
    policy action_type([:read, :update]) do
      # Guest checkout: Anyone can access orders in checkout state (UUID security)
      authorize_if expr(state == :checkout)
      # Completed orders: Only the owner can access orders in order state
      authorize_if expr(state == :order and user_id == ^actor(:id))
    end
  end

  pub_sub do
    module EdenflowersWeb.Endpoint
    publish_all :update, ["order", "updated", :_pkey]
  end

  attributes do
    uuid_primary_key :id

    attribute :order_number, :integer do
      writable? false
      generated? true
      primary_key? false
      allow_nil? false
    end

    attribute :step, :integer, default: 1, constraints: [min: 1, max: 4]

    # When checkout is completed the state is set to :order
    attribute :state, :atom,
      default: :checkout,
      constraints: [one_of: [:checkout, :order]]

    attribute :ordered_at, :utc_datetime

    attribute :payment_status, :atom,
      default: :pending,
      constraints: [
        one_of: [
          :pending,
          :paid,
          :failed,
          :refunded
        ]
      ]

    attribute :fulfillment_status, :atom,
      default: :pending,
      constraints: [
        one_of: [
          :pending,
          :fulfilled
        ]
      ]

    # Step 1 - Your Details
    attribute :customer_name, :string
    attribute :customer_email, :string

    # Step 2 - Gift Options
    attribute :gift, :boolean, default: false
    attribute :gift_message, :string

    # Step 3 - Delivery Information
    attribute :recipient_name, :string
    attribute :recipient_phone_number, :string
    attribute :delivery_address, :string
    attribute :delivery_instructions, :string
    attribute :fulfillment_date, :date
    attribute :fulfillment_amount, :decimal
    attribute :calculated_address, :string
    attribute :here_id, :string
    attribute :distance, :integer
    attribute :position, :string

    # Step 4 - Payment
    attribute :payment_intent_id, :string

    attribute :locale, :string, default: "sv-FI"

    timestamps()
  end

  relationships do
    belongs_to :user, Edenflowers.Accounts.User
    belongs_to :fulfillment_option, Edenflowers.Store.FulfillmentOption
    belongs_to :promotion, Edenflowers.Store.Promotion
    has_many :line_items, Edenflowers.Store.LineItem
  end

  calculations do
    calculate :order_reference, :string, {Edenflowers.Store.Order.EncodeOrderReference, []}
    calculate :promotion_applied?, :boolean, expr(not is_nil(promotion_id))
    calculate :total, :decimal, expr(line_total + (fulfillment_amount || 0))

    calculate :fulfillment_tax_amount,
              :decimal,
              expr(
                if is_nil(fulfillment_option_id) do
                  0
                else
                  (fulfillment_amount || 0) * fulfillment_option.tax_rate.percentage
                end
              )

    calculate :tax_amount, :decimal, expr(line_tax_amount + fulfillment_tax_amount)
  end

  aggregates do
    sum :total_items_in_cart, :line_items, :quantity
    sum :line_total, :line_items, :line_total
    sum :line_tax_amount, :line_items, :line_tax_amount
    sum :discount_amount, :line_items, :discount_amount
  end
end

defmodule Edenflowers.Store.Order.EncodeOrderReference do
  use Ash.Resource.Calculation

  alias Edenflowers.Sqids

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def calculate(records, _opts, _context) do
    Enum.map(records, fn record ->
      case Map.get(record, :order_number) do
        nil -> nil
        order_number -> Sqids.encode!([order_number])
      end
    end)
  end
end

defmodule Edenflowers.Store.Order.ClearGiftFields do
  use Ash.Resource.Change

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      gift = Ash.Changeset.get_argument_or_attribute(changeset, :gift)

      if not gift do
        Ash.Changeset.force_change_attributes(changeset, %{
          recipient_name: nil,
          gift_message: nil
        })
      else
        changeset
      end
    end)
  end
end

defmodule Edenflowers.Store.Order.MaybeRequireRecipientName do
  use Ash.Resource.Change

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def change(changeset, _opts, _context) do
    if Ash.Changeset.get_argument_or_attribute(changeset, :gift) do
      Ash.Changeset.require_values(changeset, :update, false, [:recipient_name])
    else
      changeset
    end
  end
end

defmodule Edenflowers.Store.Order.MaybeRequireDeliveryAddress do
  use Ash.Resource.Change

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def change(changeset, _opts, _context) do
    fulfillment_option = Ash.Changeset.get_argument_or_attribute(changeset, :fulfillment_option)

    if not is_nil(fulfillment_option) and fulfillment_option.fulfillment_method == :delivery do
      Ash.Changeset.require_values(changeset, :update, false, [:delivery_address])
    else
      changeset
    end
  end
end

defmodule Edenflowers.Store.Order.ValidateAndCalculateFulfillment do
  use Ash.Resource.Change
  use Gettext, backend: EdenflowersWeb.Gettext

  alias Edenflowers.{HereAPI, Fulfillments}

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      fulfillment_option = Ash.Changeset.get_argument_or_attribute(changeset, :fulfillment_option)

      if fulfillment_option.fulfillment_method == :delivery do
        with {:ok, delivery_address} <- get_delivery_address(changeset),
             {:ok, {calculated_address, position, here_id}} <- HereAPI.get_address(delivery_address),
             {:ok, distance} <- HereAPI.get_distance(position),
             {:ok, fulfillment_amount} <- Fulfillments.calculate_price(fulfillment_option, distance) do
          Ash.Changeset.force_change_attributes(changeset,
            fulfillment_amount: fulfillment_amount,
            delivery_address: delivery_address,
            calculated_address: calculated_address,
            position: position,
            here_id: here_id,
            distance: distance
          )
        else
          {:error, :delivery_address_is_empty} ->
            Ash.Changeset.add_error(changeset, %Ash.Error.Changes.Required{field: :delivery_address})

          {:error, :out_of_delivery_range} ->
            Ash.Changeset.add_error(changeset, %Ash.Error.Changes.InvalidAttribute{
              field: :delivery_address,
              message: gettext("Outside delivery range")
            })

          {:error, :address_not_found} ->
            Ash.Changeset.add_error(changeset, %Ash.Error.Changes.InvalidAttribute{
              field: :delivery_address,
              message: gettext("Address not found")
            })

          _ ->
            Ash.Changeset.add_error(changeset, %Ash.Error.Changes.InvalidAttribute{
              field: :delivery_address,
              message: gettext("There was a problem calculating delivery cost, please try again later")
            })
        end
      else
        {:ok, fulfillment_amount} = Fulfillments.calculate_price(fulfillment_option)

        Ash.Changeset.force_change_attributes(changeset,
          fulfillment_amount: fulfillment_amount,
          delivery_address: nil,
          delivery_instructions: nil,
          calculated_address: nil,
          position: nil,
          here_id: nil,
          distance: nil
        )
      end
    end)
  end

  defp get_delivery_address(changeset) do
    case Ash.Changeset.get_argument_or_attribute(changeset, :delivery_address) do
      nil -> {:error, :delivery_address_is_empty}
      "" -> {:error, :delivery_address_is_empty}
      delivery_address -> {:ok, delivery_address}
    end
  end
end

defmodule Edenflowers.Store.Order.LookupPromotionCode do
  use Ash.Resource.Change
  use Gettext, backend: EdenflowersWeb.Gettext

  alias Edenflowers.Store.Promotion

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      case Promotion.get_by_code(changeset.arguments.code) do
        {:ok, promotion} ->
          Ash.Changeset.force_change_attributes(changeset, promotion_id: promotion.id)

        _ ->
          Ash.Changeset.add_error(changeset, %Ash.Error.Changes.InvalidAttribute{
            field: :code,
            message: gettext("Invalid code")
          })
      end
    end)
  end
end

defmodule Edenflowers.Store.Order.UpsertUserAndAssignToOrder do
  use Ash.Resource.Change
  import Edenflowers.Actors

  alias Edenflowers.Accounts.User

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      customer_email = Ash.Changeset.get_argument_or_attribute(changeset, :customer_email)
      customer_name = Ash.Changeset.get_argument_or_attribute(changeset, :customer_name)

      case User.upsert(customer_email, customer_name, actor: system_actor()) do
        {:ok, user} ->
          Ash.Changeset.force_change_attributes(changeset, user_id: user.id)

        {:error, _error} ->
          changeset
      end
    end)
  end
end
