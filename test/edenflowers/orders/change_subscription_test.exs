defmodule Edenflowers.Orders.ChangeSubscriptionTest do
  use Edenflowers.DataCase, async: true

  import Generator
  import Mox

  alias Edenflowers.External.StripeAPI
  alias Edenflowers.Orders
  alias Edenflowers.Orders.Subscription
  alias Edenflowers.Payments

  setup :verify_on_exit!

  setup do
    product = generate(product())

    %{
      customer: generate(admin_user(admin: false)),
      admin: generate(admin_user()),
      medium: generate(product_variant(product_id: product.id, size: :medium, draft: false)),
      large: generate(product_variant(product_id: product.id, size: :large, draft: false)),
      fulfillment_option_id: generate(fulfillment_option(fulfillment_method: :delivery)).id
    }
  end

  defp subscription(context, attrs \\ %{}) do
    Ash.Seed.seed!(
      Subscription,
      Map.merge(
        %{
          user_id: context.customer.id,
          product_variant_id: context.medium.id,
          fulfillment_option_id: context.fulfillment_option_id,
          interval_weeks: 2,
          next_fulfillment_date: days_from_today(14),
          locale: "en",
          stripe_customer_id: "cus_1",
          stripe_payment_method_id: "pm_old"
        },
        attrs
      )
    )
  end

  defp days_from_today(days), do: "Europe/Helsinki" |> DateTime.now!() |> DateTime.to_date() |> Date.add(days)

  describe "changing size and how often" do
    test "keeps the next date, so the change applies from the next occurrence", context do
      subscription = subscription(context)

      changed =
        Orders.change_subscription!(subscription, %{product_variant_id: context.large.id, interval_weeks: 4},
          actor: context.customer
        )

      assert changed.product_variant_id == context.large.id
      assert changed.interval_weeks == 4
      assert changed.next_fulfillment_date == subscription.next_fulfillment_date
    end

    test "only to another size of the same product", context do
      subscription = subscription(context)
      bouquet = generate(product_variant(product_id: generate(product()).id, draft: false))
      draft = generate(product_variant(product_id: context.medium.product_id, size: :small, draft: true))

      for variant <- [bouquet, draft] do
        assert {:error, %Ash.Error.Invalid{errors: [%{field: :product_variant_id}]}} =
                 Orders.change_subscription(subscription, %{product_variant_id: variant.id}, actor: context.customer)
      end
    end

    test "only to an interval on offer", context do
      assert {:error, %Ash.Error.Invalid{}} =
               Orders.change_subscription(subscription(context), %{interval_weeks: 3}, actor: context.customer)
    end

    test "respects the cutoff, except for Jennie", context do
      subscription = subscription(context, %{next_fulfillment_date: days_from_today(4)})

      assert {:error, %Ash.Error.Invalid{errors: [%{message: "It's too late to change your next delivery."}]}} =
               Orders.change_subscription(subscription, %{interval_weeks: 4}, actor: context.customer)

      assert Orders.change_subscription!(subscription, %{interval_weeks: 4}, actor: context.admin).interval_weeks == 4
    end

    test "not once cancelled, nor on someone else's", context do
      cancelled = subscription(context, %{state: :cancelled})
      theirs = subscription(context, %{user_id: generate(admin_user(admin: false)).id})

      assert {:error, %Ash.Error.Invalid{}} =
               Orders.change_subscription(cancelled, %{interval_weeks: 4}, actor: context.customer)

      assert {:error, %Ash.Error.Forbidden{}} =
               Orders.change_subscription(theirs, %{interval_weeks: 4}, actor: context.customer)
    end
  end

  describe "replacing the card" do
    test "opens a SetupIntent on the subscription's Stripe Customer", context do
      subscription = subscription(context)
      subscription_id = subscription.id

      expect(StripeAPI.Mock, :create_setup_intent, fn "cus_1", %{"subscription_id" => ^subscription_id} ->
        {:ok, %{id: "seti_1", client_secret: "seti_1_secret"}}
      end)

      assert {:ok, "seti_1_secret"} = Payments.setup_card_replacement(subscription)
    end

    test "stores the card the SetupIntent saved", context do
      subscription = subscription(context)
      expect_setup_intent("seti_1", subscription)

      assert {:ok, _} = Payments.save_subscription_card("seti_1", context.customer)

      assert %{stripe_payment_method_id: "pm_new", state: :active} = Ash.reload!(subscription, authorize?: false)
    end

    test "returns a held subscription to active from the first date not past", context do
      subscription = subscription(context, %{state: :payment_failed, next_fulfillment_date: days_from_today(-3)})
      expect_setup_intent("seti_1", subscription)

      assert {:ok, _} = Payments.save_subscription_card("seti_1", context.customer)

      assert %{stripe_payment_method_id: "pm_new", state: :active, next_fulfillment_date: next_date} =
               Ash.reload!(subscription, authorize?: false)

      assert next_date == Date.add(subscription.next_fulfillment_date, 14)
    end

    test "saving the same card again changes nothing", context do
      subscription = subscription(context, %{state: :payment_failed, next_fulfillment_date: days_from_today(10)})
      setup_intent = setup_intent("seti_1", subscription)

      assert {:ok, _} = Payments.save_subscription_card(setup_intent, Edenflowers.Actors.system_actor())
      assert {:ok, _} = Payments.save_subscription_card(setup_intent, Edenflowers.Actors.system_actor())

      assert %{stripe_payment_method_id: "pm_new", state: :active, next_fulfillment_date: next_date} =
               Ash.reload!(subscription, authorize?: false)

      assert next_date == days_from_today(10)
    end

    test "a customer can't save a card to someone else's subscription", context do
      theirs = subscription(context, %{user_id: generate(admin_user(admin: false)).id})
      expect_setup_intent("seti_theirs", theirs)

      assert {:error, _} = Payments.save_subscription_card("seti_theirs", context.customer)

      assert Ash.reload!(theirs, authorize?: false).stripe_payment_method_id == "pm_old"
    end

    test "ignores a SetupIntent that hasn't succeeded", context do
      subscription = subscription(context)

      assert {:error, :not_a_saved_subscription_card} =
               Payments.save_subscription_card(
                 %{setup_intent("seti_1", subscription) | status: "requires_payment_method"},
                 context.customer
               )
    end
  end

  defp expect_setup_intent(id, subscription) do
    expect(StripeAPI.Mock, :retrieve_setup_intent, fn ^id -> {:ok, setup_intent(id, subscription)} end)
  end

  defp setup_intent(id, subscription) do
    %{
      id: id,
      status: "succeeded",
      payment_method: "pm_new",
      metadata: %{"subscription_id" => subscription.id}
    }
  end
end
