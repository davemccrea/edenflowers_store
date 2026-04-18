defmodule Edenflowers.Workers.SendNewsletterPromoEmailTest do
  use Edenflowers.DataCase
  import Swoosh.TestAssertions
  import Edenflowers.Actors

  alias Edenflowers.Accounts.User
  alias Edenflowers.Store.Promotion
  alias Edenflowers.Workers.SendNewsletterPromoEmail

  defp subscribe(email) do
    {:ok, user} = User.subscribe_to_newsletter(email, authorize?: false)
    user
  end

  defp seed_promo(usage) do
    Ash.Seed.seed!(Promotion, %{
      name: "Newsletter Welcome",
      code: "NEWSLETTER-AABBCC",
      discount_percentage: Decimal.new("0.15"),
      minimum_cart_total: Decimal.new("0"),
      usage_limit: 1,
      usage: usage
    })
  end

  defp run(email), do: perform_job(SendNewsletterPromoEmail, %{"email" => email, "locale" => "en"})

  describe "first subscription" do
    test "creates a promo, sends welcome email, and sets newsletter_promo_id on user" do
      user = subscribe("new@example.com")

      assert :ok = run("new@example.com")

      assert_email_sent(fn email ->
        assert email.subject =~ "15%"
        assert hd(email.to) == {"", "new@example.com"}
      end)

      {:ok, user} = User.get_by_email(user.email, authorize?: false, load: [:newsletter_promo])
      assert user.newsletter_promo_id != nil
      assert to_string(user.newsletter_promo.code) =~ ~r/^newsletter-[0-9a-f]{6}$/
    end
  end

  describe "re-subscription with unused code" do
    test "sends reminder email containing the existing code" do
      user = subscribe("existing@example.com")
      promo = seed_promo(0)
      User.set_newsletter_promo(user, promo.id, actor: system_actor())

      assert :ok = run("existing@example.com")

      assert_email_sent(fn email ->
        assert email.text_body =~ to_string(promo.code)
      end)
    end
  end

  describe "re-subscription with used code" do
    test "sends welcome-back email without including the code" do
      user = subscribe("returning@example.com")
      promo = seed_promo(1)
      User.set_newsletter_promo(user, promo.id, actor: system_actor())

      assert :ok = run("returning@example.com")

      assert_email_sent(fn email ->
        refute email.text_body =~ to_string(promo.code)
      end)
    end
  end
end
