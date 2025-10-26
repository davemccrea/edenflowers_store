defmodule Edenflowers.Workers.SendOrderConfirmationEmail do
  @moduledoc false

  use Oban.Worker
  import Edenflowers.Actors

  alias Edenflowers.Email
  alias Edenflowers.Mailer
  alias Edenflowers.Store.Order

  def perform(%Oban.Job{args: %{"order_id" => order_id}}) do
    load =
    [

    # Aggregates
    :line_total,
    :line_tax_amount,
    :discount_amount,

    # Calculations
    :order_reference,
    :promotion_applied?,
    :total,
    :tax_amount,
    :fulfillment_tax_amount,

    # Relationships
    :promotion,
    fulfillment_option: [:tax_rate],
    line_items: [:line_total, :line_tax_amount, :discount_amount]
    ]

    order_id
    |> Order.get_by_id!(load: load, actor: system_actor())
    |> Email.order_confirmation()
    |> Mailer.deliver()
  end
end
