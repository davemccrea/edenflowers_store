defmodule Edenflowers.Minimossen do
  @moduledoc """
  Entry point for Minimossen sales: what Jennie sells through Minimossen's shared
  Winpos till, imported from the weekly reports Stormossen emails to the shop.
  """

  use Ash.Domain,
    otp_app: :edenflowers,
    extensions: [AshAdmin.Domain]

  admin do
    show?(true)
  end

  resources do
    resource Edenflowers.Minimossen.WeeklySales do
      define :record_minimossen_sales, action: :record
      define :import_winpos_reports, action: :import_reports
      define :recent_minimossen_sales, action: :recent_sales
    end
  end
end
