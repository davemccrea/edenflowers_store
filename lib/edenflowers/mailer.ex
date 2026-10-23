defmodule Edenflowers.Mailer do
  @moduledoc """
  Swoosh mailer used to deliver customer, shop, and error-alert emails.
  """

  use Swoosh.Mailer, otp_app: :edenflowers
end
