defmodule Edenflowers.Email.Templates do
  @moduledoc """
  Plain-text email templates compiled at build time. Each entry in `@templates`
  becomes a public render function named after the template, so
  `Edenflowers.Email` can stay focused on building Swoosh envelopes.
  """

  require EEx
  use GettextSigils, backend: EdenflowersWeb.Gettext

  @templates [
    {:order_confirmation, [:assigns]},
    {:newsletter_promo, [:assigns]},
    {:newsletter_already_subscribed, [:assigns]},
    {:newsletter_resubscribed, [:_assigns]},
    {:otp_sign_in, [:assigns]}
  ]

  for {name, args} <- @templates do
    EEx.function_from_file(
      :def,
      name,
      Path.join([__DIR__, "templates", "#{name}.text.eex"]),
      args
    )
  end
end
