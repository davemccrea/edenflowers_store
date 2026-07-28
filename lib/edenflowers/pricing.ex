defmodule Edenflowers.Pricing do
  use Ash.Domain,
    otp_app: :edenflowers,
    extensions: [AshAdmin.Domain]

  admin do
    show?(true)
  end

  resources do
    resource Edenflowers.Pricing.TaxRate

    resource Edenflowers.Pricing.Promotion do
      define :get_promotion_by_id, action: :by_id, args: [:id], get?: true
      define :get_promotion_by_code, action: :by_code, args: [:code, {:optional, :today}], get?: true
      define :increment_promotion_usage, action: :increment_usage
      define :create_newsletter_promotion, action: :create_for_newsletter
    end
  end
end
