defmodule Edenflowers.Pricing.Workers.SendNewsletterPromoEmailTest do
  use Edenflowers.DataCase, async: true
  import Swoosh.TestAssertions
  import Edenflowers.Actors

  alias Edenflowers.Pricing

  alias Edenflowers.Accounts
  alias Edenflowers.Pricing.Workers.SendNewsletterPromoEmail

  describe "first subscription" do
    test "creates a promo, sends welcome email, and sets newsletter_promo_id on user" do
      {:ok, user} = Accounts.subscribe_to_newsletter("new@example.com", "en-GB", authorize?: false)

      assert :ok = perform_job(SendNewsletterPromoEmail, %{"email" => "new@example.com", "locale" => "en"})

      assert_email_sent(fn email ->
        assert email.to == [{"", "new@example.com"}]
        assert {"Jennie", _address} = email.from
        assert email.text_body =~ "\nJennie\nEden Flowers\n"
        assert email.subject == "Your 15% welcome code for Eden Flowers"
      end)

      {:ok, user} = Accounts.get_user_by_email(user.email, authorize?: false, load: [:newsletter_promo])
      assert user.newsletter_promo_id != nil
      assert to_string(user.newsletter_promo.code) =~ ~r/^[0-9A-F]{6}$/
    end
  end

  describe "re-subscription with unused code" do
    test "sends reminder email containing the existing code" do
      {:ok, promo} = Pricing.create_newsletter_promotion(actor: system_actor())
      {:ok, user} = Accounts.subscribe_to_newsletter("existing@example.com", "en-GB", authorize?: false)
      {:ok, _} = Accounts.set_newsletter_promo(user, promo.id, actor: system_actor())

      assert :ok = perform_job(SendNewsletterPromoEmail, %{"email" => "existing@example.com", "locale" => "en"})

      assert_email_sent(fn email ->
        assert email.to == [{"", "existing@example.com"}]
        assert email.text_body =~ to_string(promo.code)
      end)
    end
  end

  describe "re-subscription with an expired, unused code" do
    test "sends welcome-back email without offering the expired code" do
      {:ok, promo} = Pricing.create_newsletter_promotion(actor: system_actor())

      {:ok, promo} =
        Ash.update(promo, %{expiration_date: Date.add(Edenflowers.ShopTime.today(), -2)}, authorize?: false)

      {:ok, user} = Accounts.subscribe_to_newsletter("lapsed@example.com", "en-GB", authorize?: false)
      {:ok, _} = Accounts.set_newsletter_promo(user, promo.id, actor: system_actor())

      assert :ok = perform_job(SendNewsletterPromoEmail, %{"email" => "lapsed@example.com", "locale" => "en"})

      assert_email_sent(fn email ->
        refute email.text_body =~ to_string(promo.code)
        assert {"Eden Flowers", _address} = email.from
        assert email.subject == "You're already subscribed to the Eden Flowers newsletter"
      end)
    end
  end

  describe "re-subscription with used code" do
    test "sends welcome-back email without including the code" do
      {:ok, promo} = Pricing.create_newsletter_promotion(actor: system_actor())
      Generator.use_promotion(promo)
      {:ok, user} = Accounts.subscribe_to_newsletter("returning@example.com", "en-GB", authorize?: false)
      {:ok, _} = Accounts.set_newsletter_promo(user, promo.id, actor: system_actor())

      assert :ok = perform_job(SendNewsletterPromoEmail, %{"email" => "returning@example.com", "locale" => "en"})

      assert_email_sent(fn email ->
        email.to == [{"", "returning@example.com"}] and
          email.subject == "You're already subscribed to the Eden Flowers newsletter" and
          not (email.text_body =~ to_string(promo.code))
      end)
    end
  end

  describe "enqueue" do
    test "is not swallowed by another worker's recent job for the same email" do
      {:ok, _} =
        Edenflowers.Accounts.Workers.SendOtpEmail.enqueue(%{
          "email" => "otp@example.com",
          "otp_code" => "123456",
          "locale" => "en"
        })

      {:ok, job} = SendNewsletterPromoEmail.enqueue(%{"email" => "otp@example.com", "locale" => "en"})

      refute job.conflict?
      assert_enqueued(worker: SendNewsletterPromoEmail, args: %{"email" => "otp@example.com"})
    end
  end

  describe "locale scoping" do
    test "does not leak job's locale into the caller's process state" do
      Gettext.put_locale(EdenflowersWeb.Gettext, "en")
      {:ok, _user} = Accounts.subscribe_to_newsletter("scope@example.com", "en-GB", authorize?: false)

      assert :ok = perform_job(SendNewsletterPromoEmail, %{"email" => "scope@example.com", "locale" => "fi"})

      assert Gettext.get_locale(EdenflowersWeb.Gettext) == "en"
    end
  end
end
