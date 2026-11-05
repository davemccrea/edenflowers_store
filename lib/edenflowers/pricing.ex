defmodule Edenflowers.Pricing do
  @moduledoc """
  Entry point for VAT rates and promotion codes.

  `TaxRate` supplies the rate applied to products, courses, and fulfillment;
  `Promotion` holds discount terms and tracks code use; `WelcomeOffer` is the
  rate new newsletter subscribers' codes are generated with.
  """

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
      define :start_promotion_validity, action: :start_validity
      define :create_pass_it_on_batch, action: :create_pass_it_on_batch, args: [:name, :count]
    end

    resource Edenflowers.Pricing.Promotion.Version

    resource Edenflowers.Pricing.WelcomeOffer do
      define :get_welcome_offer, action: :get
      define :update_welcome_offer, action: :update
    end
  end
end
