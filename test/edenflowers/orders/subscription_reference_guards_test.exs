defmodule Edenflowers.Orders.SubscriptionReferenceGuardsTest do
  use Edenflowers.DataCase, async: true

  import Generator

  setup do
    product = generate(product(subscribable: true, free_delivery: true))
    variant = generate(product_variant(product_id: product.id))
    subscription = generate(subscription(product_variant_id: variant.id))

    %{product: product, variant: variant, subscription: subscription}
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

  test "allows the changes once the subscription is cancelled", context do
    context.subscription
    |> Ash.Changeset.for_update(:cancel)
    |> Ash.update!(authorize?: false)

    assert {:ok, _product} =
             context.product
             |> Ash.Changeset.for_update(:update, %{subscribable: false, free_delivery: false})
             |> Ash.update(authorize?: false)

    assert :ok = Ash.destroy(context.variant, authorize?: false)
  end
end
