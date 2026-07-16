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
      define :get_user_by_subject, action: :get_by_subject, args: [:subject]
      define :get_user_by_email, action: :get_by_email, args: [:email]
      define :upsert_user, action: :upsert, args: [:email, :name]
      define :request_otp, action: :request_otp, args: [:email]
      define :sign_in_with_otp, action: :sign_in_with_otp, args: [:email, :otp]
      define :subscribe_to_newsletter, action: :subscribe_to_newsletter, args: [:email]
      define :update_user_name, action: :update_name, args: [:name]
      define :update_newsletter_preference, action: :update_newsletter_preference, args: [:newsletter_opt_in]
      define :set_newsletter_promo, action: :set_newsletter_promo, args: [:newsletter_promo_id]
    end

    resource Edenflowers.Accounts.UserIdentity
  end
end
