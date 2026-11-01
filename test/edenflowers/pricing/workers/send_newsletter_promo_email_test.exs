defmodule Edenflowers.Pricing.Workers.SendNewsletterPromoEmailTest do
  use Edenflowers.DataCase, async: true
  import Swoosh.TestAssertions
  import Edenflowers.Actors

  alias Edenflowers.Pricing

  alias Edenflowers.Accounts
  alias Edenflowers.Pricing.Workers.SendNewsletterPromoEmail

  describe "signing up queues the welcome email" do
    test "the signup action records the opt-in and enqueues the worker" do
      {:ok, user} = Accounts.subscribe_to_newsletter("direct@example.com", "fi", authorize?: false)

      assert user.newsletter_opt_in
      assert_enqueued(worker: SendNewsletterPromoEmail, args: %{"email" => "direct@example.com", "locale" => "fi"})
    end

    test "signing up twice queues one job" do
      {:ok, _} = Accounts.subscribe_to_newsletter("twice@example.com", "fi", authorize?: false)
      {:ok, _} = Accounts.subscribe_to_newsletter("twice@example.com", "fi", authorize?: false)

      assert [_job] = all_enqueued(worker: SendNewsletterPromoEmail)
    end

    test "a failed signup records no opt-in and queues nothing" do
      assert {:error, _} = Accounts.subscribe_to_newsletter("failed@example.com", "xx", authorize?: false)

      assert {:error, _} = Accounts.get_user_by_email("failed@example.com", authorize?: false)
      refute_enqueued(worker: SendNewsletterPromoEmail)
    end

    test "opting in through the preference toggle queues nothing" do
      {:ok, user} = Accounts.upsert_user("toggle@example.com", "Toggle", authorize?: false)
      {:ok, _} = Accounts.update_newsletter_preference(user, true, "fi", actor: user)

      refute_enqueued(worker: SendNewsletterPromoEmail)
    end
  end

  describe "first subscription" do
    test "signup gives the code at once and the welcome email sends it" do
      {:ok, user} = Accounts.subscribe_to_newsletter("new@example.com", "en-GB", authorize?: false)
      assert_enqueued(worker: SendNewsletterPromoEmail, args: %{"email" => "new@example.com", "welcome" => true})

      {:ok, user} = Accounts.get_user_by_email(user.email, authorize?: false, load: [:newsletter_promo])
      code = to_string(user.newsletter_promo.code)
      assert code =~ ~r/^[0-9A-F]{6}$/

      assert :ok =
               perform_job(SendNewsletterPromoEmail, %{
                 "email" => "new@example.com",
                 "locale" => "en",
                 "welcome" => true
               })

      assert_email_sent(fn email ->
        assert email.to == [{"", "new@example.com"}]
        assert {"Jennie", _address} = email.from
        assert email.text_body =~ "\nJennie\nEden Flowers\n"
        assert email.text_body =~ code
        assert email.subject == "Your 15% welcome code for Eden Flowers"
      end)
    end

    test "the welcome email names the rate on the subscriber's own code" do
      Pricing.get_welcome_offer!()
      |> Pricing.update_welcome_offer!(%{discount_rate: "0.25"}, authorize?: false)

      {:ok, _user} = Accounts.subscribe_to_newsletter("offer@example.com", "fi", authorize?: false)

      Pricing.get_welcome_offer!()
      |> Pricing.update_welcome_offer!(%{discount_rate: "0.15"}, authorize?: false)

      assert :ok =
               perform_job(SendNewsletterPromoEmail, %{
                 "email" => "offer@example.com",
                 "locale" => "en",
                 "welcome" => true
               })

      assert_email_sent(fn email ->
        assert email.subject == "Your 25% welcome code for Eden Flowers"
        assert email.text_body =~ "you get 25% off one order"
      end)
    end

    test "signing up again keeps the first code and queues the already-subscribed wording" do
      {:ok, first} = Accounts.subscribe_to_newsletter("again@example.com", "fi", authorize?: false)
      # Clears the first signup's job, which would otherwise swallow the second as a duplicate.
      Ecto.Adapters.SQL.query!(Edenflowers.Repo, "DELETE FROM oban_jobs")
      {:ok, second} = Accounts.subscribe_to_newsletter("again@example.com", "fi", authorize?: false)

      assert second.newsletter_promo_id == first.newsletter_promo_id
      assert_enqueued(worker: SendNewsletterPromoEmail, args: %{"email" => "again@example.com", "welcome" => false})
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

  describe "re-subscription with an admin-edited code" do
    defp resubscribe_with(email, edits) do
      {:ok, promo} = Pricing.create_newsletter_promotion(actor: system_actor())
      {:ok, promo} = Ash.update(promo, edits, authorize?: false)
      {:ok, user} = Accounts.subscribe_to_newsletter(email, "en-GB", authorize?: false)
      {:ok, _} = Accounts.set_newsletter_promo(user, promo.id, actor: system_actor())
      promo
    end

    defp assert_offered(email, promo, offered?) do
      assert :ok = perform_job(SendNewsletterPromoEmail, %{"email" => email, "locale" => "en"})
      assert_email_sent(fn sent -> assert sent.text_body =~ to_string(promo.code) == offered? end)
      assert offered? == match?({:ok, _}, Pricing.get_promotion_by_code(to_string(promo.code)))
    end

    test "offers a code with no expiration date" do
      promo = resubscribe_with("open@example.com", %{expiration_date: nil})
      assert_offered("open@example.com", promo, true)
    end

    test "offers a code expiring today" do
      promo = resubscribe_with("today@example.com", %{expiration_date: Edenflowers.ShopTime.today()})
      assert_offered("today@example.com", promo, true)
    end

    test "withholds a code that starts tomorrow" do
      tomorrow = Date.add(Edenflowers.ShopTime.today(), 1)
      promo = resubscribe_with("future@example.com", %{start_date: tomorrow})
      assert_offered("future@example.com", promo, false)
    end

    test "offers a used code whose usage limit was raised" do
      promo = resubscribe_with("raised@example.com", %{usage_limit: 2})
      Generator.use_promotion(promo)
      assert_offered("raised@example.com", promo, true)
    end

    test "offers a used code whose usage limit was removed" do
      promo = resubscribe_with("unlimited@example.com", %{usage_limit: nil})
      Generator.use_promotion(promo)
      assert_offered("unlimited@example.com", promo, true)
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
