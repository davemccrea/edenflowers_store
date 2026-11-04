defmodule Edenflowers.Bank do
  @moduledoc """
  The shop's S-Pankki account, read through Enable Banking.

  `Connection` holds the consent Jennie gives by logging in to her bank. Its
  booked payments mark expenses and invoices paid.
  """

  use Ash.Domain,
    otp_app: :edenflowers,
    extensions: [AshAdmin.Domain]

  admin do
    show?(true)
  end

  resources do
    resource Edenflowers.Bank.Connection do
      define :current_bank_connection, action: :current, not_found_error?: false
      define :bank_authorization_url, action: :authorization_url, args: [:state, :redirect_url]
      define :connect_bank, action: :connect, args: [:code]
    end
  end
end
