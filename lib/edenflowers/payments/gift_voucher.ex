defmodule Edenflowers.Payments.GiftVoucher do
  @moduledoc """
  A Gift voucher: money paid in advance that whoever holds its code spends on
  flowers, subscriptions and courses. It pays like money, not like a
  Promotion: each use is a `:voucher` `Payment` pointing at it, and handing
  back what it paid for is a negative one. What's left is its amount less
  those payments, so there's no separate balance to keep in step.

  The code is long and random because it is money; lookups are rate-limited
  where customers enter it.
  """
  use Ash.Resource,
    domain: Edenflowers.Payments,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  require Ash.Query

  import Ash.Expr, only: [expr: 1]

  @valid_for_years 1
  @code_length 12
  @alphabet "0123456789ABCDEFGHJKMNPQRSTVWXYZ"

  postgres do
    repo Edenflowers.Repo
    table "gift_vouchers"
    migration_types amount: :decimal

    check_constraints do
      check_constraint :amount, "gift_vouchers_valid_amount",
        check: "amount > 0 AND amount = round(amount, 2)",
        message: "must be a positive amount in whole cents"
    end

    references do
      reference :line_item, on_delete: :restrict
    end
  end

  actions do
    defaults [:read]

    create :create do
      description "Issues a voucher for the line that sold it, with a new random code, valid for one year from " <>
                    "today in Helsinki."

      accept [:amount, :line_item_id]
      change set_attribute(:code, &__MODULE__.generate_code/0)
      change set_attribute(:expires_on, &__MODULE__.default_expiry/0)
    end

    read :by_code do
      description "The voucher with this code, however the customer typed it: spaces, dashes and case are " <>
                    "ignored. Found whether or not it can still pay, so the customer is told why not."

      argument :code, :string, allow_nil?: false
      get? true
      prepare build(load: [:remaining, :expired?, :cancelled?, :spendable?])

      prepare fn query, _context ->
        code = normalize_code(Ash.Query.get_argument(query, :code))
        Ash.Query.filter(query, code == ^code)
      end
    end
  end

  policies do
    bypass actor_attribute_equals(:system, true) do
      authorize_if always()
    end

    bypass actor_attribute_equals(:admin, true) do
      authorize_if always()
    end

    # Holding the code is the access, as with a Payment Link's token.
    policy action(:by_code) do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :code, :string do
      description "What the holder enters to spend it: 12 characters, stored without the dashes it's printed with."
      allow_nil? false
      sensitive? true
    end

    attribute :amount, :decimal do
      description "What it was bought for, in euros."
      allow_nil? false
      constraints scale: 2
    end

    attribute :expires_on, :date do
      description "The last day it can pay, one year after it was bought."
      allow_nil? false
    end

    timestamps()
  end

  relationships do
    belongs_to :line_item, Edenflowers.Orders.LineItem do
      description "The order line that sold it, so its money is the order's like any sale."
      allow_nil? false
    end

    has_many :payments, Edenflowers.Payments.Payment do
      description "What it paid, positive, and what was handed back onto it, negative."
    end
  end

  calculations do
    calculate :remaining, :decimal, expr(amount - spent) do
      description "What's left on it in euros: its amount less what it has paid, net of what was handed back onto it."
    end

    calculate :expired?, :boolean, expr(expires_on < helsinki_today()) do
      description "Whether its last day has passed in Helsinki."
    end

    calculate :cancelled?, :boolean, expr(line_item.order.fulfillment_status == :cancelled) do
      description "Whether the order that sold it was cancelled, refunding it, so it can no longer pay."
    end

    calculate :spendable?, :boolean, expr(not expired? and not cancelled? and remaining > 0) do
      description "Whether it can pay for anything now: not expired, its sale not cancelled, and something left on it."
    end
  end

  aggregates do
    # Unauthorized so a guest checking a code counts everyone's spending, not just their own.
    sum :spent, :payments, :amount do
      description "What it has paid in euros, net of what was handed back onto it."
      default Decimal.new("0")
      authorize? false
    end
  end

  identities do
    identity :unique_code, [:code]
    identity :one_per_line, [:line_item_id]
  end

  @doc """
  A new code: 12 random characters of Crockford's base32, 60 bits, so
  guessing one is hopeless. The alphabet leaves out I, L, O and U, which
  are misread as 1 and 0 or spell words.
  """
  def generate_code do
    # 256 is a multiple of 32, so each byte picks a character without bias.
    for <<byte <- :crypto.strong_rand_bytes(@code_length)>>, into: "", do: <<:binary.at(@alphabet, rem(byte, 32))>>
  end

  @doc "The expiry of a voucher bought today."
  def default_expiry, do: Date.shift(Edenflowers.ShopTime.today(), year: @valid_for_years)

  @doc """
  A code as the customer might type it, reduced to how it's stored: case,
  spaces and dashes ignored, and the letters left out of codes read as the
  digits they're mistaken for.
  """
  def normalize_code(code) do
    code
    |> String.upcase()
    |> String.replace(~r/[^0-9A-Z]/, "")
    |> String.replace("O", "0")
    |> String.replace(["I", "L"], "1")
  end

  @doc "A code as it's printed: groups of four, easier to read out and type."
  def format_code(code), do: code |> String.graphemes() |> Enum.chunk_every(4) |> Enum.join("-")
end
