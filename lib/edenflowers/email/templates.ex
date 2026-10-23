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
    {:order_details, [:assigns]},
    {:order_bill, [:assigns]},
    {:order_totals, [:assigns]},
    {:payment_failed, [:assigns]},
    {:subscription_set_up, [:assigns]},
    {:order_fulfilled, [:assigns]},
    {:order_left_at_door, [:assigns]},
    {:order_cancelled, [:assigns]},
    {:order_refunded, [:assigns]},
    {:course_confirmation, [:assigns]},
    {:course_payment_link, [:assigns]},
    {:booking_cancelled, [:assigns]},
    {:booking_refunded, [:assigns]},
    {:newsletter_promo, [:assigns]},
    {:newsletter_already_subscribed, [:assigns]},
    {:newsletter_resubscribed, [:assigns]},
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
