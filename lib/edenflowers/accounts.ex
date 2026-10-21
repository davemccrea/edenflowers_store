defmodule Edenflowers.Accounts do
  use Ash.Domain,
    otp_app: :edenflowers,
    extensions: [AshAdmin.Domain]

  admin do
    show?(true)
  end

  resources do
    resource Edenflowers.Accounts.Token

    resource Edenflowers.Accounts.PushSubscription do
      define :subscribe_to_push, action: :subscribe, args: [:endpoint, :p256dh, :auth, :locale]
      define :get_push_subscription, action: :read, get_by: [:endpoint]
      define :list_push_subscriptions, action: :read
      define :list_admin_push_subscriptions, action: :admin_devices
      define :unsubscribe_from_push, action: :destroy
    end

    resource Edenflowers.Accounts.User do
      define :get_customer_for_admin, action: :admin_show, get_by: [:id]
      define :search_customers, action: :search, args: [:term]
      define :get_user_by_email, action: :get_by_email, args: [:email]
      define :upsert_user, action: :upsert, args: [:email, :name]
      define :list_newsletter_subscribers, action: :newsletter_subscribers
      define :subscribe_to_newsletter, action: :subscribe_to_newsletter, args: [:email, :locale]
      define :update_name, action: :update, args: [:name]
      define :change_email, action: :change_email, args: [:email]
      define :update_newsletter_preference, action: :update, args: [:newsletter_opt_in, :locale]
      define :ensure_stripe_customer, action: :ensure_stripe_customer
      define :forget_stripe_customer, action: :forget_stripe_customer
      define :set_newsletter_promo, action: :set_newsletter_promo, args: [:newsletter_promo_id]
    end
  end
end
