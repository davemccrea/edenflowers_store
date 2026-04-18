defmodule Edenflowers.Workers.SendNewsletterPromoEmailTest do
  use Edenflowers.DataCase
  import Swoosh.TestAssertions
  import Edenflowers.Actors

  alias Edenflowers.Accounts.User
  alias Edenflowers.Store.Promotion
  alias Edenflowers.Workers.SendNewsletterPromoEmail

  describe "first subscription" do
    test "creates a promo, sends welcome email, and sets newsletter_promo_id on user" do
      {:ok, user} = User.subscribe_to_newsletter("new@example.com", authorize?: false)

      assert :ok = perform_job(SendNewsletterPromoEmail, %{"email" => "new@example.com", "locale" => "en"})

      assert_email_sent(fn email ->
        assert email.to == [{"", "new@example.com"}]
        assert email.subject =~ "Welcome"
      end)

      {:ok, user} = User.get_by_email(user.email, authorize?: false, load: [:newsletter_promo])
      assert user.newsletter_promo_id != nil
      assert to_string(user.newsletter_promo.code) =~ "NEWSLETTER-"
    end
  end

  describe "re-subscription with unused code" do
    test "sends reminder email containing the existing code" do
      {:ok, promo} = Promotion.create_for_newsletter(actor: system_actor())
      {:ok, user} = User.subscribe_to_newsletter("existing@example.com", authorize?: false)
      {:ok, _} = User.set_newsletter_promo(user, promo.id, actor: system_actor())

      assert :ok = perform_job(SendNewsletterPromoEmail, %{"email" => "existing@example.com", "locale" => "en"})

      assert_email_sent(fn email ->
        assert email.to == [{"", "existing@example.com"}]
        assert email.text_body =~ to_string(promo.code)
      end)
    end
  end

  describe "re-subscription with used code" do
    test "sends welcome-back email without including the code" do
      {:ok, promo} = Promotion.create_for_newsletter(actor: system_actor())
      {:ok, promo} = Promotion.increment_usage(promo, actor: system_actor())
      {:ok, user} = User.subscribe_to_newsletter("returning@example.com", authorize?: false)
      {:ok, _} = User.set_newsletter_promo(user, promo.id, actor: system_actor())

      assert :ok = perform_job(SendNewsletterPromoEmail, %{"email" => "returning@example.com", "locale" => "en"})

      assert_email_sent(fn email ->
        email.to == [{"", "returning@example.com"}] and
          email.subject =~ "Welcome back to the Eden Flowers newsletter" and
          not (email.text_body =~ to_string(promo.code))
      end)
    end
  end
end
