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
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshTranslation.Resource]

  alias Edenflowers.Fulfillment.Availability
  alias Edenflowers.Fulfillment.Fee

  postgres do
    table "fulfillment_options"
    repo Edenflowers.Repo
    migration_types base_price: :decimal, price_per_km: :decimal

    check_constraints do
      check_constraint :base_price, "fulfillment_options_valid_base_price",
        check: "base_price >= 0 AND base_price = round(base_price, 2)",
        message: "must be a non-negative amount in whole cents"

      check_constraint :price_per_km, "fulfillment_options_valid_price_per_km",
        check: "price_per_km >= 0 AND price_per_km = round(price_per_km, 2)",
        message: "must be a non-negative amount in whole cents"
    end
  end

  translations do
    locales Edenflowers.Locales.translatable_atoms()
    fields [:name]
  end

  actions do
    defaults [
      :read,
      :destroy,
      create: [
        :name,
        :sort_key,
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
        :tax_rate_id,
        :translations
      ],
      update: [
        :name,
        :sort_key,
        :fulfillment_method,
        :rate_type,
        :base_price,
        :price_per_km,
        :free_dist_km,
        :max_dist_km,
        :same_day,
        :order_deadline,
        :tax_rate_id,
        :translations
      ]
    ]

    read :list_for_checkout do
      prepare build(sort: [sort_key: :asc, name: :asc])
    end

    update :update_calendar do
      description "Admin-only update narrowed to the calendar overrides. " <>
                    "Prevents accidental writes to pricing or fulfillment-method attrs."

      accept [:available_days, :enabled_dates, :disabled_dates]
    end

    update :toggle_date do
      description "Toggle a single date on or off, mutating enabled_dates / disabled_dates per the click semantics in Changes.ToggleDate."
      # The change reads the existing option to compute the new override sets,
      # so it can't be expressed as a single DB expression.
      require_atomic? false
      argument :date, :date, allow_nil?: false
      change Edenflowers.Fulfillment.FulfillmentOption.Changes.ToggleDate
    end

    update :set_weekday do
      description "Set a weekday's rule to :on or :off, idempotently. Prunes now-redundant overrides per Changes.SetWeekday."
      require_atomic? false
      argument :weekday, Edenflowers.Fulfillment.Weekday, allow_nil?: false
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
      change set_attribute(:available_days, Edenflowers.Fulfillment.Weekday.all())
      change set_attribute(:enabled_dates, [])
      change set_attribute(:disabled_dates, [])
    end

    action :calculate_delivery, :map do
      argument :delivery_address, :string, allow_nil?: false
      argument :fulfillment_option_id, :uuid, allow_nil?: false

      run fn input, _context ->
        here_api = Application.get_env(:edenflowers, :here_api, Edenflowers.External.HereAPI)
        delivery_address = input.arguments.delivery_address
        option_id = input.arguments.fulfillment_option_id

        with {:ok, option} <- Ash.get(__MODULE__, option_id, authorize?: false),
             {:ok, {geocoded_address, position, here_id}} <- here_api.geocode(delivery_address),
             {:ok, distance} <- here_api.route_distance(position) do
          case Fee.calculate(option, distance) do
            %{error: nil, fulfillment_fee: fulfillment_fee} ->
              {:ok,
               %{
                 error: nil,
                 geocoded_address: geocoded_address,
                 position: position,
                 here_id: here_id,
                 distance: distance,
                 fulfillment_fee: fulfillment_fee
               }}

            %{error: reason} ->
              {:ok, %{error: reason}}
          end
        else
          {:error, reason} -> {:ok, %{error: reason}}
        end
      end
    end

    action :fulfill_on_date, :atom do
      description "Why the option can't be fulfilled on `date`, or nil when it can. Returns " <>
                    "{:ok, nil} when bookable and {:ok, reason} when not — a non-bookable date " <>
                    "is a normal result, not an error, so it stays out of Ash.Error.Unknown."

      allow_nil? true
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
          {:ok, Availability.unavailable_reason(option, date, now)}
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

    validate compare(:free_dist_km, less_than_or_equal_to: :max_dist_km) do
      where attribute_equals(:rate_type, :dynamic)
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false, public?: true
    attribute :sort_key, :integer, default: 0, allow_nil?: false, public?: true

    attribute :fulfillment_method, Edenflowers.Fulfillment.FulfillmentOption.FulfillmentMethod,
      allow_nil?: false,
      public?: true

    attribute :rate_type, Edenflowers.Fulfillment.FulfillmentOption.RateType, allow_nil?: false, public?: true
    attribute :base_price, :decimal, allow_nil?: false, public?: true, constraints: [min: 0, scale: 2]
    attribute :price_per_km, :decimal, public?: true, constraints: [min: 0, scale: 2]
    attribute :free_dist_km, :integer, public?: true, constraints: [min: 0]
    attribute :max_dist_km, :integer, public?: true, constraints: [min: 1]

    attribute :same_day, :boolean, default: false, public?: true
    attribute :order_deadline, :time, public?: true

    attribute :available_days, {:array, Edenflowers.Fulfillment.Weekday},
      default: Edenflowers.Fulfillment.Weekday.all(),
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
