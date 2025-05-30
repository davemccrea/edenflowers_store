defmodule Edenflowers.Store.Order do
  use Ash.Resource,
    domain: Edenflowers.Store,
    data_layer: AshPostgres.DataLayer,
    notifiers: [Ash.Notifier.PubSub]

  use Gettext, backend: EdenflowersWeb.Gettext

  require Ash.Resource.Change.Builtins

  alias Edenflowers.Store.Order.{
    ProcessFulfillment,
    MaybeRequireDeliveryAddress,
    LookupPromotionCode,
    MaybeRequireRecipientName,
    ClearGiftFields
  }

  postgres do
    repo Edenflowers.Repo
    table "orders"
  end

  @load [
    # Aggregates
    :total_items_in_cart,
    :discount_amount,

    # Calculations
    :promotion_applied?,
    :total,
    :tax_amount,
    :fulfillment_tax_amount,

    # Relationships
    :promotion,
    :fulfillment_option,
    :line_items
  ]

  postgres do
    repo Edenflowers.Repo
    table "orders"
  end

  code_interface do
    define :create_for_checkout, action: :create_for_checkout
    define :get_by_id, action: :get_by_id, args: [:id]
    define :get_for_checkout, action: :get_for_checkout, args: [:id]
    define :payment_received, action: :payment_received
    define :add_payment_intent_id, action: :add_payment_intent_id, args: [:payment_intent_id]
    define :add_promotion_with_id, action: :add_promotion_with_id, args: [:promotion_id]
    define :add_promotion_with_code, action: :add_promotion_with_code, args: [:code]
    define :clear_promotion, action: :clear_promotion
    define :update_fulfillment_option, action: :update_fulfillment_option, args: [:fulfillment_option_id]
    define :update_gift, action: :update_gift, args: [:gift]
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

    read :get_for_checkout do
      argument :id, :uuid, allow_nil?: false
      filter expr(id == ^arg(:id))
      get? true
      prepare build(load: @load)
    end

    # Create Actions
    create :create_for_checkout do
      change set_attribute(:step, 1)
      change load(@load)
    end

    # Step-specific Update Actions
    update :edit_step_1 do
      change set_attribute(:step, 1)
      change load(@load)
    end

    update :save_step_1 do
      accept [:customer_name, :customer_email]
      require_attributes [:customer_name, :customer_email]
      change set_attribute(:step, 2)
      change load(@load)
      require_atomic? false
    end

    update :edit_step_2 do
      change set_attribute(:step, 2)
      change load(@load)
    end

    update :save_step_2 do
      accept [:gift, :recipient_name, :gift_message]
      change set_attribute(:step, 3)
      change {MaybeRequireRecipientName, []}
      change {ClearGiftFields, []}
      change load(@load)
      require_atomic? false
    end

    update :edit_step_3 do
      change set_attribute(:step, 3)
      change load(@load)
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
      change {ProcessFulfillment, []}
      change set_attribute(:step, 4)
      change load(@load)

      require_atomic? false
    end

    update :save_step_4 do
      accept []
    end

    # Other Update Actions
    update :payment_received do
      change set_attribute(:state, :order)
      change set_attribute(:payment_status, :paid)
    end

    update :update_fulfillment_option do
      accept [:fulfillment_option_id]
      # When filfillment_option is updated, clear chosen fulfillment date
      change set_attribute(:fulfillment_date, nil)
      change load(@load)
    end

    update :update_gift do
      accept [:gift]
      change load(@load)
    end

    update :add_payment_intent_id do
      accept [:payment_intent_id]
      change load(@load)
    end

    update :add_promotion_with_id do
      argument :promotion_id, :uuid, allow_nil?: false
      change atomic_update(:promotion_id, expr(^arg(:promotion_id)))
      change load(@load)
    end

    update :add_promotion_with_code do
      argument :code, :string
      change {LookupPromotionCode, []}
      change load(@load)
      require_atomic? false
    end

    update :clear_promotion do
      change set_attribute(:promotion_id, nil)
      change load(@load)
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
      change load(@load)
    end
  end

  pub_sub do
    module EdenflowersWeb.Endpoint
    publish_all :update, ["order", "updated", :_pkey]
  end

  attributes do
    uuid_primary_key :id

    attribute :step, :integer, default: 1, constraints: [min: 1, max: 4]

    # When checkout is completed the state is set to :order
    attribute :state, :atom,
      default: :checkout,
      constraints: [one_of: [:checkout, :order]]

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

    timestamps()
  end

  relationships do
    belongs_to :fulfillment_option, Edenflowers.Store.FulfillmentOption
    belongs_to :promotion, Edenflowers.Store.Promotion
    has_many :line_items, Edenflowers.Store.LineItem
  end

  calculations do
    calculate :promotion_applied?, :boolean, expr(not is_nil(promotion_id))
    calculate :total, :decimal, expr(line_total + (fulfillment_amount || 0))

    calculate :fulfillment_tax_amount,
              :decimal,
              expr((fulfillment_amount || 0) * fulfillment_option.tax_rate.percentage)

    calculate :tax_amount, :decimal, expr(line_tax_amount + fulfillment_tax_amount)
  end

  aggregates do
    sum :total_items_in_cart, :line_items, :quantity
    sum :line_total, :line_items, :line_total
    sum :line_tax_amount, :line_items, :line_tax_amount
    sum :discount_amount, :line_items, :discount_amount
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

defmodule Edenflowers.Store.Order.ProcessFulfillment do
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
            message: "Invalid code"
          })
      end
    end)
  end
end
