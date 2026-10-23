defmodule Edenflowers.Email.Templates do
  @moduledoc """
  Plain-text email templates compiled at build time. Each entry in `@templates`
  becomes a public render function named after the template, so
  `Edenflowers.Email` can stay focused on building Swoosh envelopes.
  """

  use GettextSigils, backend: EdenflowersWeb.Gettext

  require EEx

  @templates [
    {:order_confirmation, [:assigns]},
    {:payment_received, [:assigns]},
    {:purchase_receipt, [:assigns]},
    {:booking_payment_received, [:assigns]},
    {:payment_reminder, [:assigns]},
    {:booking_payment_reminder, [:assigns]},
    {:order_details, [:assigns]},
    {:order_updated, [:assigns]},
    {:order_totals, [:assigns]},
    {:order_fulfillment, [:assigns]},
    {:order_payment, [:assigns]},
    {:subscription_payment_failed, [:assigns]},
    {:subscription_set_up, [:assigns]},
    {:subscription_charged, [:assigns]},
    {:subscription_cancelled, [:assigns]},
    {:subscription_cancellation_confirmed, [:assigns]},
    {:order_delivered, [:assigns]},
    {:order_left_at_door, [:assigns]},
    {:order_cancelled, [:assigns]},
    {:cancellation_confirmed, [:assigns]},
    {:refund_line, [:assigns]},
    {:order_refunded, [:assigns]},
    {:course_confirmation, [:assigns]},
    {:course_payment_link, [:assigns]},
    {:booking_cancelled, [:assigns]},
    {:booking_refunded, [:assigns]},
    {:newsletter, [:assigns]},
    {:otp_sign_in, [:assigns]},
    {:email_change_code, [:assigns]},
    {:wedding_enquiry, [:assigns]}
  ]

  for {name, args} <- @templates do
    EEx.function_from_file(
      :def,
      name,
      Path.join([__DIR__, "templates", "#{name}.text.eex"]),
      args
    )
  end

  @doc "Jennie's shop, where pickup orders are collected."
  def shop_address, do: "Minimossen, #{~t"Myrvägen 1"}, #{~t"65230 Vasa"}"

  @doc """
  Jennie's own words for this email, as a paragraph after the line saying
  what happened, or nothing.
  """
  def message(nil), do: ""
  def message(""), do: ""
  def message(text), do: String.trim(text) <> "\n\n"

  @doc "How the emails Jennie sends are signed."
  def signature do
    """
    Jennie
    Eden Flowers
    #{shop_address()}
    040 220 9494 · edenflowers.fi\
    """
  end
end
