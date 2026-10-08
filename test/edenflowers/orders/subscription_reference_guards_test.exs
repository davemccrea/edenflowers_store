defmodule Edenflowers.Orders.SubscriptionReferenceGuardsTest do
  use Edenflowers.DataCase, async: true

  import Generator

  alias Edenflowers.Orders.Subscription

  setup do
    product = generate(product(subscribable: true, free_delivery: true))
    variant = generate(product_variant(product_id: product.id))
    fulfillment_option = generate(fulfillment_option(fulfillment_method: :delivery))

    subscription =
      Ash.Seed.seed!(Subscription, %{
        user_id: generate(admin_user(admin: false)).id,
        product_variant_id: variant.id,
        fulfillment_option_id: fulfillment_option.id,
        state: :active,
        interval_weeks: 2,
        next_fulfillment_date: Date.add(Date.utc_today(), 14),
        locale: "en",
        stripe_customer_id: "cus_1",
        stripe_payment_method_id: "pm_1"
      })

    %{product: product, variant: variant, fulfillment_option: fulfillment_option, subscription: subscription}
  end

  test "does not archive a variant used by a current subscription", %{variant: variant} do
    assert {:error, %Ash.Error.Invalid{errors: errors}} = Ash.destroy(variant, authorize?: false)
    assert Enum.any?(errors, &(&1.field == :id))
  end

  test "does not remove a product's subscription promises", %{product: product} do
    assert {:error, %Ash.Error.Invalid{errors: errors}} =
             product
             |> Ash.Changeset.for_update(:update, %{subscribable: false, free_delivery: false})
             |> Ash.update(authorize?: false)

    assert Enum.any?(errors, &(&1.field == :subscribable))
    assert Enum.any?(errors, &(&1.field == :free_delivery))
  end

  test "does not change a subscription's delivery option to pickup", %{fulfillment_option: option} do
    assert {:error, %Ash.Error.Invalid{errors: errors}} =
             option
             |> Ash.Changeset.for_update(:update, %{fulfillment_method: :pickup})
             |> Ash.update(authorize?: false)

    assert Enum.any?(errors, &(&1.field == :fulfillment_method))
  end

  test "allows the changes once the subscription is cancelled", context do
    context.subscription
    |> Ash.Changeset.for_update(:cancel)
    |> Ash.update!(authorize?: false)

    assert {:ok, _product} =
             context.product
             |> Ash.Changeset.for_update(:update, %{subscribable: false, free_delivery: false})
             |> Ash.update(authorize?: false)

    assert {:ok, _option} =
             context.fulfillment_option
             |> Ash.Changeset.for_update(:update, %{fulfillment_method: :pickup})
             |> Ash.update(authorize?: false)

    assert :ok = Ash.destroy(context.variant, authorize?: false)
  end
end
