defmodule Edenflowers.Fulfillment.ShopCalendar do
  @moduledoc """
  The days the shop is open, shared by every fulfillment option. Jennie is one
  florist, so delivery and pickup go out on the same days.

  There is one row. `:get` creates it on first use, open every day with
  same-day off. It reads before creating, as the create's upsert locks the
  row and checkout reads it on every page.
  """
  use Ash.Resource,
    otp_app: :edenflowers,
    domain: Edenflowers.Fulfillment,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Edenflowers.Fulfillment.Changes
  alias Edenflowers.Fulfillment.Weekday

  postgres do
    table "shop_calendar"
    repo Edenflowers.Repo
  end

  actions do
    defaults [:read]

    action :get, :struct do
      constraints instance_of: __MODULE__

      run fn _input, context ->
        opts = Ash.Context.to_opts(context)

        case Ash.read_one(__MODULE__, opts) do
          {:ok, nil} -> Ash.create(__MODULE__, %{}, Keyword.put(opts, :action, :create))
          result -> result
        end
      end
    end

    create :create do
      upsert? true
      upsert_identity :singleton
      upsert_fields [:singleton]
    end

    update :update_same_day do
      accept [:same_day, :order_deadline]
    end

    update :toggle_date do
      description "Toggle a single date on or off, mutating enabled_dates / disabled_dates per the click semantics in Changes.ToggleDate."
      # The change reads the existing calendar to compute the new override
      # sets, so it can't be expressed as a single DB expression.
      require_atomic? false
      argument :date, :date, allow_nil?: false
      change Changes.ToggleDate
    end

    update :set_weekday do
      description "Set a weekday's rule to :on or :off, idempotently. Prunes now-redundant overrides per Changes.SetWeekday."
      require_atomic? false
      argument :weekday, Weekday, allow_nil?: false
      argument :direction, :atom, allow_nil?: false, constraints: [one_of: [:on, :off]]
      change Changes.SetWeekday
    end

    update :set_week do
      description "Set every non-past date in `week` to :open or :closed, idempotently."
      require_atomic? false
      argument :week, {:array, :date}, allow_nil?: false
      argument :today, :date, allow_nil?: false
      argument :direction, :atom, allow_nil?: false, constraints: [one_of: [:open, :closed]]
      change Changes.SetWeek
    end

    update :reset_calendar do
      description "Reset the calendar to fully-open / no overrides. Destructive, so the admin reset button confirms before invoking."
      change set_attribute(:available_days, Weekday.all())
      change set_attribute(:enabled_dates, [])
      change set_attribute(:disabled_dates, [])
    end
  end

  policies do
    bypass actor_attribute_equals(:admin, true) do
      authorize_if always()
    end

    policy action([:read, :get, :create]) do
      authorize_if always()
    end

    policy action_type(:update) do
      forbid_if always()
    end
  end

  validations do
    validate present(:order_deadline) do
      where attribute_equals(:same_day, true)
    end
  end

  attributes do
    uuid_primary_key :id

    # Always true, so the unique identity on it allows one row.
    attribute :singleton, :boolean, allow_nil?: false, default: true, writable?: false

    attribute :same_day, :boolean, allow_nil?: false, default: false, public?: true
    attribute :order_deadline, :time, public?: true

    attribute :available_days, {:array, Weekday},
      allow_nil?: false,
      default: Weekday.all(),
      public?: true

    attribute :enabled_dates, {:array, :date}, allow_nil?: false, default: [], public?: true
    attribute :disabled_dates, {:array, :date}, allow_nil?: false, default: [], public?: true
  end

  identities do
    identity :singleton, [:singleton]
  end
end
