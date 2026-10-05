defmodule Edenflowers.Accounts do
  use Ash.Domain,
    otp_app: :edenflowers,
    extensions: [AshAdmin.Domain]

  admin do
    show?(true)
  end

  resources do
    resource Edenflowers.Accounts.Token

    resource Edenflowers.Accounts.User do
      define :get_customer_for_admin, action: :admin_show, get_by: [:id]
      define :get_user_by_email, action: :get_by_email, args: [:email]
      define :upsert_user, action: :upsert, args: [:email, :name]
      define :subscribe_to_newsletter, action: :subscribe_to_newsletter, args: [:email]
      define :update_newsletter_preference, action: :update, args: [:newsletter_opt_in]
      define :set_newsletter_promo, action: :set_newsletter_promo, args: [:newsletter_promo_id]
    end
  end
end
