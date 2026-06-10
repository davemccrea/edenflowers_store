defmodule Edenflowers.Fulfillment.FulfillmentOption.RateType do
  use Ash.Type.Enum, values: [:fixed, :dynamic]
end

defmodule Edenflowers.Fulfillment.FulfillmentOption.FulfillmentMethod do
  use Ash.Type.Enum, values: [:delivery, :pickup]
end

defmodule Edenflowers.Fulfillment.FulfillmentOption do
  use Ash.Resource,
    otp_app: :edenflowers,
    domain: Edenflowers.Fulfillment,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Edenflowers.Fulfillment.FulfillmentCalendar

  postgres do
    table "fulfillment_options"
    repo Edenflowers.Repo
  end

  code_interface do
    define :list, action: :read
    define :list_for_checkout, action: :list_for_checkout
    define :get_by_id, action: :by_id, args: [:id]
    define :update_calendar, action: :update_calendar
    define :toggle_date, action: :toggle_date, args: [:date]
    define :set_weekday, action: :set_weekday, args: [:weekday, :direction]
    define :set_week, action: :set_week, args: [:week, :today, :direction]
    define :reset_calendar, action: :reset_calendar
    define :calculate_delivery, action: :calculate_delivery, args: [:delivery_address, :fulfillment_option_id]
    define :calculate_price, action: :calculate_price, args: [:fulfillment_option_id, :distance]
    define :fulfill_on_date, action: :fulfill_on_date, args: [:fulfillment_option_id, :date]
  end

  actions do
    defaults [
      :read,
      :destroy,
      create: [
        :name,
        :sort_key,
        :minimum_cart_total,
        :fulfillment_method,
        :rate_type,
        :base_price,
        :price_per_km,
        :free_dist_km,
        :max_dist_km,
        :same_day,
        :order_deadline,
        :available_days,
        :enabled_dates,
        :disabled_dates,
        :tax_rate_id
      ],
      update: [
        :name,
        :sort_key,
        :minimum_cart_total,
        :fulfillment_method,
        :rate_type,
        :base_price,
        :price_per_km,
        :free_dist_km,
        :max_dist_km,
        :same_day,
        :order_deadline,
        :tax_rate_id
      ]
    ]

    read :by_id do
      argument :id, :uuid, allow_nil?: false
      filter expr(id == ^arg(:id))
      get? true
    end

    read :list_for_checkout do
      prepare build(sort: [sort_key: :asc, name: :asc])
    end

    update :update_calendar do
      description "Admin-only update narrowed to the calendar overrides. " <>
                    "Prevents accidental writes to pricing or fulfillment-method attrs."

      accept [:available_days, :enabled_dates, :disabled_dates]
    end

    update :toggle_date do
      description "Toggle a single date on or off, mutating enabled_dates / disabled_dates per the click semantics in FulfillmentCalendar."
      # The change reads the existing option to compute the new override sets,
      # so it can't be expressed as a single DB expression.
      require_atomic? false
      argument :date, :date, allow_nil?: false
      change Edenflowers.Fulfillment.FulfillmentOption.Changes.ToggleDate
    end

    update :set_weekday do
      description "Set a weekday's rule to :on or :off, idempotently. Prunes now-redundant overrides per FulfillmentCalendar."
      require_atomic? false
      argument :weekday, :atom, allow_nil?: false
      argument :direction, :atom, allow_nil?: false, constraints: [one_of: [:on, :off]]
      change Edenflowers.Fulfillment.FulfillmentOption.Changes.SetWeekday
    end

    update :set_week do
      description "Set every non-past date in `week` to :open or :closed, idempotently."
      require_atomic? false
      argument :week, {:array, :date}, allow_nil?: false
      argument :today, :date, allow_nil?: false
      argument :direction, :atom, allow_nil?: false, constraints: [one_of: [:open, :closed]]
      change Edenflowers.Fulfillment.FulfillmentOption.Changes.SetWeek
    end

    update :reset_calendar do
      description "Reset the calendar to fully-open / no overrides. Destructive — the admin reset button confirms before invoking."
      require_atomic? false
      change Edenflowers.Fulfillment.FulfillmentOption.Changes.ResetCalendar
    end

    action :calculate_delivery, :map do
      argument :delivery_address, :string, allow_nil?: false
      argument :fulfillment_option_id, :uuid, allow_nil?: false

      run fn input, _context ->
        here_api = Application.get_env(:edenflowers, :here_api, Edenflowers.External.HereAPI)
        delivery_address = input.arguments.delivery_address
        option_id = input.arguments.fulfillment_option_id

        with {:ok, option} <- Ash.get(__MODULE__, option_id, authorize?: false),
             {:ok, {geocoded_address, position, here_id}} <- here_api.get_address(delivery_address),
             {:ok, distance} <- here_api.get_distance(position),
             {:ok, fulfillment_fee} <- calculate_price(option_id, distance, authorize?: false) do
          {:ok,
           %{
             error: nil,
             geocoded_address: geocoded_address,
             position: position,
             here_id: here_id,
             distance: distance,
             fulfillment_fee: fulfillment_fee
           }}
        else
          {:error, reason} ->
            {:ok, %{error: reason}}
        end
      end
    end

    action :calculate_price, :decimal do
      argument :fulfillment_option_id, :uuid, allow_nil?: false
      argument :distance, :decimal, default: Decimal.new("0")

      run fn input, _context ->
        option_id = input.arguments.fulfillment_option_id
        distance = input.arguments.distance

        with {:ok, option} <- Ash.get(__MODULE__, option_id, authorize?: false) do
          case option.rate_type do
            :fixed ->
              {:ok, option.base_price}

            :dynamic ->
              %{
                price_per_km: price_per_km,
                base_price: base_price,
                free_dist_km: free_dist_km,
                max_dist_km: max_dist_km
              } = option

              price_per_m = Decimal.div(price_per_km, 1000)
              free_dist_m = Decimal.mult(free_dist_km, 1000)
              max_dist_m = Decimal.mult(max_dist_km, 1000)

              cond do
                Decimal.lte?(distance, free_dist_m) ->
                  {:ok, Decimal.new("0")}

                Decimal.gt?(distance, free_dist_m) and Decimal.lt?(distance, max_dist_m) ->
                  {:ok,
                   distance
                   |> Decimal.sub(free_dist_m)
                   |> Decimal.mult(price_per_m)
                   |> Decimal.add(base_price)
                   |> Decimal.round(2)}

                true ->
                  {:error, :out_of_delivery_range}
              end
          end
        end
      end
    end

    action :fulfill_on_date, :map do
      description "Whether the option can be fulfilled on `date`. Returns a tagged map: " <>
                    "%{error: nil} when bookable, or %{error: reason} when not. The tagged map " <>
                    "keeps the reason out of Ash.Error.Unknown so callers can match on it directly."
      argument :fulfillment_option_id, :uuid, allow_nil?: false
      argument :date, :date, allow_nil?: false
      argument :now, :utc_datetime, default: &DateTime.utc_now/0

      run fn input, _context ->
        option_id = input.arguments.fulfillment_option_id
        date = input.arguments.date
        # `unavailable_reason/3` expects Helsinki-local time for the same-day
        # deadline comparison, so normalise the incoming UTC `now`.
        now = DateTime.shift_zone!(input.arguments.now, "Europe/Helsinki")

        with {:ok, option} <- Ash.get(__MODULE__, option_id, authorize?: false) do
          {:ok, %{error: FulfillmentCalendar.unavailable_reason(option, date, now)}}
        end
      end
    end
  end

  policies do
    bypass actor_attribute_equals(:admin, true) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if always()
    end

    policy action_type(:action) do
      authorize_if always()
    end

    policy action_type([:create, :update, :destroy]) do
      description "All mutations require admin actor (covered by bypass above)."
      forbid_if always()
    end
  end

  validations do
    validate present([:price_per_km, :free_dist_km, :max_dist_km]) do
      where attribute_equals(:rate_type, :dynamic)
    end

    validate present(:order_deadline) do
      where attribute_equals(:same_day, true)
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false, public?: true
    attribute :sort_key, :integer, default: 0, allow_nil?: false, public?: true

    attribute :minimum_cart_total, :decimal, default: 0, public?: true

    attribute :fulfillment_method, Edenflowers.Fulfillment.FulfillmentOption.FulfillmentMethod,
      allow_nil?: false,
      public?: true

    attribute :rate_type, Edenflowers.Fulfillment.FulfillmentOption.RateType, allow_nil?: false, public?: true
    attribute :base_price, :decimal, allow_nil?: false, public?: true
    attribute :price_per_km, :decimal, public?: true
    attribute :free_dist_km, :integer, public?: true
    attribute :max_dist_km, :integer, public?: true

    attribute :same_day, :boolean, default: false, public?: true
    attribute :order_deadline, :time, public?: true

    attribute :available_days, {:array, :atom},
      default: [:monday, :tuesday, :wednesday, :thursday, :friday, :saturday, :sunday],
      public?: true

    attribute :enabled_dates, {:array, :date}, default: [], public?: true
    attribute :disabled_dates, {:array, :date}, default: [], public?: true
  end

  relationships do
    belongs_to :tax_rate, Edenflowers.Pricing.TaxRate, allow_nil?: false, public?: true
  end

  identities do
    identity :unique_name, [:name]
  end
end
