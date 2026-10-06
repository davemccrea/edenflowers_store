defmodule Edenflowers.Pricing do
  use Ash.Domain,
    otp_app: :edenflowers,
    extensions: [AshAdmin.Domain]

  admin do
    show?(true)
  end

  resources do
    resource Edenflowers.Pricing.TaxRate do
      define :list_selectable_tax_rates, action: :selectable
      define :retire_tax_rate, action: :retire
    end

    resource Edenflowers.Pricing.Promotion do
      define :get_promotion_by_id, action: :read, get_by: [:id]
      define :get_promotion_by_code, action: :by_code, args: [:code, {:optional, :today}], get?: true
      define :create_newsletter_promotion, action: :create_for_newsletter
    end

    resource Edenflowers.Pricing.Promotion.Version
  end
end
