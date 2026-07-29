defmodule Edenflowers.Orders.OrderTest do
  use Edenflowers.DataCase
  import Generator
  alias Edenflowers.Orders
  alias Edenflowers.Accounts

  describe "Store Resource" do
    test "creates an order for checkout" do
      order = Orders.create_for_checkout!(authorize?: false)
      assert order.state == :contact_details
    end

    test "counts number of items in cart" do
      tax_rate = generate(tax_rate())
      product_1 = generate(product(tax_rate_id: tax_rate.id))
      product_1_product_variant_1 = generate(product_variant(product_id: product_1.id))
      product_2 = generate(product(tax_rate_id: tax_rate.id))
      product_2_product_variant_1 = generate(product_variant(product_id: product_2.id))
      order = generate(order())

      _line_item_1 =
        generate(
          line_item(
            order_id: order.id,
            product_variant_id: product_1_product_variant_1.id,
            quantity: 2
          )
        )

      _line_item_2 =
        generate(
          line_item(
            order_id: order.id,
            product_variant_id: product_2_product_variant_1.id,
            quantity: 1
          )
        )

      order = Ash.load!(order, [:total_items_in_cart], authorize?: false)

      assert order.total_items_in_cart == 3
    end

    test "sums items_subtotal and items_tax correctly when no promotion is applied" do
      tax_rate_1 = generate(tax_rate(percentage: "0.255"))
      product_1 = generate(product(tax_rate_id: tax_rate_1.id))
      product_1_product_variant_1 = generate(product_variant(product_id: product_1.id, price: "40.00"))

      tax_rate_2 = generate(tax_rate(percentage: "0.10"))
      product_2 = generate(product(tax_rate_id: tax_rate_2.id))
      product_2_product_variant_1 = generate(product_variant(product_id: product_2.id, price: "6.00"))

      order = Orders.create_for_checkout!(authorize?: false)

      generate(
        line_item(
          order_id: order.id,
          product_variant_id: product_1_product_variant_1.id,
          quantity: 2
        )
      )

      generate(
        line_item(
          order_id: order.id,
          product_variant_id: product_2_product_variant_1.id,
          quantity: 1
        )
      )

      order = Ash.load!(order, [:items_subtotal, :items_tax], authorize?: false)

      assert Decimal.equal?(order.items_subtotal, "86.00")
      assert Decimal.equal?(order.items_tax, "21.00")
    end

    test "sums items_subtotal and items_tax correctly when promotion is applied" do
      tax_rate = generate(tax_rate(percentage: "0.255"))
      product = generate(product(tax_rate_id: tax_rate.id))
      product_variant_1 = generate(product_variant(product_id: product.id, price: "49.99"))
      product_variant_2 = generate(product_variant(product_id: product.id, price: "29.99"))
      promotion = generate(promotion(discount_rate: "0.20", minimum_cart_total: "0"))

      order = Orders.create_for_checkout!(authorize?: false)

      generate(
        line_item(
          order_id: order.id,
          product_variant_id: product_variant_1.id,
          quantity: 1
        )
      )

      generate(
        line_item(
          order_id: order.id,
          product_variant_id: product_variant_2.id,
          quantity: 2
        )
      )

      order = Orders.add_promotion_with_id!(order, promotion.id, load: [:promotion_applied?], authorize?: false)

      order = Ash.load!(order, [:items_subtotal, :items_tax], authorize?: false)

      assert order.items_subtotal
             |> Decimal.round(2)
             |> Decimal.equal?("87.98")

      assert order.items_tax
             |> Decimal.round(2)
             |> Decimal.equal?("22.43")
    end

    test "promotion_applied? returns true if promotion applied" do
      tax_rate = generate(tax_rate())
      product = generate(product(tax_rate_id: tax_rate.id))
      product_variant = generate(product_variant(product_id: product.id))
      promotion = generate(promotion(discount_rate: "0.20", minimum_cart_total: "0"))

      order = Orders.create_for_checkout!(authorize?: false)

      generate(
        line_item(
          order_id: order.id,
          product_variant_id: product_variant.id
        )
      )

      order = Orders.add_promotion_with_id!(order, promotion.id, load: [:promotion_applied?], authorize?: false)

      assert order.promotion_applied? == true
    end

    test "promotion_applied? returns false if no promotion applied" do
      order = Orders.create_for_checkout!(authorize?: false, load: [:promotion_applied?])
      assert order.promotion_applied? == false
    end
  end

  test "calculates total and tax correctly" do
    tax_rate_2 = generate(tax_rate(percentage: "0.255"))
    tax_rate_1 = generate(tax_rate(percentage: "0.15"))
    product = generate(product(tax_rate_id: tax_rate_2.id))
    product_variant = generate(product_variant(product_id: product.id, price: "29.99"))

    fulfillment_option =
      generate(
        fulfillment_option(
          name: "Pickup",
          fulfillment_method: :pickup,
          rate_type: :fixed,
          base_price: "4.99",
          order_deadline: ~T[12:00:00],
          tax_rate_id: tax_rate_1.id
        )
      )

    {:ok, %{fulfillment_fee: fulfillment_fee}} =
      Edenflowers.Fulfillment.calculate_price(fulfillment_option.id, 0)

    order =
      generate(
        order(
          fulfillment_option_id: fulfillment_option.id,
          fulfillment_fee: fulfillment_fee,
          fulfillment_tax_percentage: tax_rate_1.percentage
        )
      )

    _line_item =
      generate(
        line_item(
          order_id: order.id,
          product_variant_id: product_variant.id,
          quantity: 2
        )
      )

    order = Ash.load!(order, [:grand_total, :tax], authorize?: false)

    assert order.grand_total
           |> Decimal.round(2)
           |> Decimal.equal?("64.97")

    assert order.tax
           |> Decimal.round(2)
           |> Decimal.equal?("16.04")
  end

  test "calling finalise_checkout updates state and payment_state" do
    order = generate(order(state: :payment, payment_intent_id: "pi_3RMvONL97TreKmaJ1hGJP2QL"))

    assert {:ok, order} = Orders.finalize_checkout(order.id, authorize?: false)
    assert order.state == :placed
    assert order.payment_status == :paid
    assert %DateTime{} = order.ordered_at
  end

  describe "Gift flow validation" do
    test "requires recipient_name when gift is true" do
      order = generate(order(state: :gift_options))

      assert {:error, error} =
               order
               |> Ash.Changeset.for_update(:submit_gift_options, %{
                 gift: true,
                 recipient_name: nil
               })
               |> Ash.update(authorize?: false)

      assert %Ash.Error.Invalid{} = error
    end

    test "does not require recipient_name when gift is false" do
      order = generate(order(state: :gift_options))

      assert {:ok, order} =
               order
               |> Ash.Changeset.for_update(:submit_gift_options, %{
                 gift: false,
                 recipient_name: nil
               })
               |> Ash.update(authorize?: false)

      assert order.gift == false
      assert is_nil(order.recipient_name)
    end

    test "accepts recipient_name when gift is true" do
      order = generate(order(state: :gift_options))

      assert {:ok, order} =
               order
               |> Ash.Changeset.for_update(:submit_gift_options, %{
                 gift: true,
                 recipient_name: "Jane Doe"
               })
               |> Ash.update(authorize?: false)

      assert order.gift == true
      assert order.recipient_name == "Jane Doe"
    end

    test "clears recipient_name and card_message when switching from gift=true to gift=false" do
      tax_rate = generate(tax_rate())
      cards_category = generate(product_category(slug: "cards"))
      card_product = generate(product(product_category_id: cards_category.id, tax_rate_id: tax_rate.id))
      order = gift_order_with_card(card_product, :medium)

      {:ok, order} =
        order
        |> Ash.Changeset.for_update(:submit_gift_options, %{
          gift: true,
          recipient_name: "John Smith",
          card_message: "Happy birthday!"
        })
        |> Ash.update(authorize?: false)

      assert order.recipient_name == "John Smith"
      assert order.card_message == "Happy birthday!"

      # Production flow: customer hits "Edit" on the gift step, returning the
      # order to :gift_options before re-submitting.
      {:ok, order} = Orders.return_to_gift_options(order, authorize?: false)

      {:ok, order} =
        order
        |> Ash.Changeset.for_update(:submit_gift_options, %{
          gift: false
        })
        |> Ash.update(authorize?: false)

      assert order.gift == false
      assert is_nil(order.recipient_name)
      assert is_nil(order.card_message)
    end

    test "accepts card_message when gift is true" do
      tax_rate = generate(tax_rate())
      cards_category = generate(product_category(slug: "cards"))
      card_product = generate(product(product_category_id: cards_category.id, tax_rate_id: tax_rate.id))
      order = gift_order_with_card(card_product, :medium)

      assert {:ok, order} =
               order
               |> Ash.Changeset.for_update(:submit_gift_options, %{
                 gift: true,
                 recipient_name: "Jane Doe",
                 card_message: "With love"
               })
               |> Ash.update(authorize?: false)

      assert order.card_message == "With love"
    end

    test "retains recipient_name when gift remains true" do
      order = generate(order(state: :gift_options))

      {:ok, order} =
        order
        |> Ash.Changeset.for_update(:submit_gift_options, %{
          gift: true,
          recipient_name: "Alice Johnson"
        })
        |> Ash.update(authorize?: false)

      {:ok, order} = Orders.return_to_gift_options(order, authorize?: false)

      {:ok, order} =
        order
        |> Ash.Changeset.for_update(:submit_gift_options, %{
          gift: true,
          recipient_name: "Alice Johnson"
        })
        |> Ash.update(authorize?: false)

      assert order.gift == true
      assert order.recipient_name == "Alice Johnson"
    end
  end

  defp gift_order_with_card(card_product, size) do
    variant = generate(product_variant(product_id: card_product.id, size: size))

    order =
      generate(order(state: :gift_options, gift: true))

    Orders.add_card!(order, variant.id, authorize?: false)
  end

  describe "Card message length validation" do
    setup do
      tax_rate = generate(tax_rate())
      cards_category = generate(product_category(slug: "cards"))
      card_product = generate(product(product_category_id: cards_category.id, tax_rate_id: tax_rate.id))
      %{card_product: card_product}
    end

    test "accepts message at exactly the small card limit", %{card_product: card_product} do
      order = gift_order_with_card(card_product, :small)
      message = String.duplicate("a", 80)

      assert {:ok, updated} =
               order
               |> Ash.Changeset.for_update(:submit_gift_options, %{
                 gift: true,
                 recipient_name: "Jane",
                 card_message: message
               })
               |> Ash.update(authorize?: false)

      assert updated.card_message == message
    end

    test "rejects message one character over the small card limit", %{card_product: card_product} do
      order = gift_order_with_card(card_product, :small)
      message = String.duplicate("a", 81)

      assert {:error, %Ash.Error.Invalid{} = error} =
               order
               |> Ash.Changeset.for_update(:submit_gift_options, %{
                 gift: true,
                 recipient_name: "Jane",
                 card_message: message
               })
               |> Ash.update(authorize?: false)

      assert Enum.any?(error.errors, &match?(%{field: :card_message}, &1))
    end

    test "accepts message at exactly the medium card limit", %{card_product: card_product} do
      order = gift_order_with_card(card_product, :medium)
      message = String.duplicate("a", 120)

      assert {:ok, _updated} =
               order
               |> Ash.Changeset.for_update(:submit_gift_options, %{
                 gift: true,
                 recipient_name: "Jane",
                 card_message: message
               })
               |> Ash.update(authorize?: false)
    end

    test "rejects message one character over the medium card limit", %{card_product: card_product} do
      order = gift_order_with_card(card_product, :medium)
      message = String.duplicate("a", 121)

      assert {:error, %Ash.Error.Invalid{}} =
               order
               |> Ash.Changeset.for_update(:submit_gift_options, %{
                 gift: true,
                 recipient_name: "Jane",
                 card_message: message
               })
               |> Ash.update(authorize?: false)
    end

    test "accepts message at exactly the large card limit", %{card_product: card_product} do
      order = gift_order_with_card(card_product, :large)
      message = String.duplicate("a", 200)

      assert {:ok, _updated} =
               order
               |> Ash.Changeset.for_update(:submit_gift_options, %{
                 gift: true,
                 recipient_name: "Jane",
                 card_message: message
               })
               |> Ash.update(authorize?: false)
    end

    test "rejects message one character over the large card limit", %{card_product: card_product} do
      order = gift_order_with_card(card_product, :large)
      message = String.duplicate("a", 201)

      assert {:error, %Ash.Error.Invalid{}} =
               order
               |> Ash.Changeset.for_update(:submit_gift_options, %{
                 gift: true,
                 recipient_name: "Jane",
                 card_message: message
               })
               |> Ash.update(authorize?: false)
    end

    test "trims leading and trailing whitespace before validation", %{card_product: card_product} do
      order = gift_order_with_card(card_product, :small)
      message = "   " <> String.duplicate("a", 80) <> "   "

      assert {:ok, updated} =
               order
               |> Ash.Changeset.for_update(:submit_gift_options, %{
                 gift: true,
                 recipient_name: "Jane",
                 card_message: message
               })
               |> Ash.update(authorize?: false)

      assert updated.card_message == String.duplicate("a", 80)
    end

    test "treats whitespace-only messages as empty", %{card_product: card_product} do
      order = gift_order_with_card(card_product, :small)

      assert {:ok, updated} =
               order
               |> Ash.Changeset.for_update(:submit_gift_options, %{
                 gift: true,
                 recipient_name: "Jane",
                 card_message: "       "
               })
               |> Ash.update(authorize?: false)

      assert is_nil(updated.card_message)
    end

    test "rejects non-empty card_message when no card line item exists" do
      order =
        Orders.create_for_checkout!(authorize?: false)
        |> Ash.Changeset.for_update(:set_gift, %{gift: true})
        |> Ash.update!(authorize?: false)

      reloaded = Orders.get_order_for_checkout!(order.id, actor: nil)

      assert {:error, %Ash.Error.Invalid{} = error} =
               reloaded
               |> Ash.Changeset.for_update(:submit_gift_options, %{
                 gift: true,
                 recipient_name: "Jane",
                 card_message: "Hello"
               })
               |> Ash.update(authorize?: false)

      assert Enum.any?(error.errors, &match?(%{field: :card_message}, &1))
    end

    test "accepts empty card_message when card is selected", %{card_product: card_product} do
      order = gift_order_with_card(card_product, :small)

      assert {:ok, _updated} =
               order
               |> Ash.Changeset.for_update(:submit_gift_options, %{
                 gift: true,
                 recipient_name: "Jane",
                 card_message: ""
               })
               |> Ash.update(authorize?: false)
    end

    test "counts graphemes not bytes", %{card_product: card_product} do
      order = gift_order_with_card(card_product, :small)
      message = String.duplicate("🌸", 80)

      assert {:ok, _updated} =
               order
               |> Ash.Changeset.for_update(:submit_gift_options, %{
                 gift: true,
                 recipient_name: "Jane",
                 card_message: message
               })
               |> Ash.update(authorize?: false)

      over_limit = String.duplicate("🌸", 81)

      assert {:error, %Ash.Error.Invalid{}} =
               order
               |> Ash.Changeset.for_update(:submit_gift_options, %{
                 gift: true,
                 recipient_name: "Jane",
                 card_message: over_limit
               })
               |> Ash.update(authorize?: false)
    end

    test "raises when line_items is not loaded on the order", %{card_product: card_product} do
      order = gift_order_with_card(card_product, :small)
      stripped = %{order | line_items: %Ash.NotLoaded{}}

      assert_raise Ash.Error.Unknown, ~r/line_items to be loaded/, fn ->
        stripped
        |> Ash.Changeset.for_update(:submit_gift_options, %{
          gift: true,
          recipient_name: "Jane",
          card_message: "Hello"
        })
        |> Ash.update(authorize?: false)
      end
    end
  end

  describe "Promotion code validation" do
    test "applies promotion using valid code" do
      tax_rate = generate(tax_rate())
      product = generate(product(tax_rate_id: tax_rate.id))
      product_variant = generate(product_variant(product_id: product.id, price: "30.00"))

      promotion =
        generate(promotion(code: "SUMMER20", discount_rate: "0.20", minimum_cart_total: "0"))

      order = Orders.create_for_checkout!(authorize?: false)

      generate(
        line_item(
          order_id: order.id,
          product_variant_id: product_variant.id
        )
      )

      assert {:ok, order} = Orders.add_promotion_with_code(order, "SUMMER20", authorize?: false)
      assert order.promotion_id == promotion.id
    end

    test "rejects invalid promotion code" do
      tax_rate = generate(tax_rate())
      product = generate(product(tax_rate_id: tax_rate.id))
      product_variant = generate(product_variant(product_id: product.id))

      order = Orders.create_for_checkout!(authorize?: false)

      generate(
        line_item(
          order_id: order.id,
          product_variant_id: product_variant.id
        )
      )

      assert {:error, error} = Orders.add_promotion_with_code(order, "INVALID", authorize?: false)
      assert %Ash.Error.Invalid{} = error
    end
  end

  describe "User upsert during checkout" do
    test "creates new user when saving step 1 with new email" do
      alias Edenflowers.Accounts.User

      order = Orders.create_for_checkout!(authorize?: false)

      assert {:error, %Ash.Error.Invalid{}} = Accounts.get_user_by_email("newcustomer@example.com", authorize?: false)

      assert {:ok, order} =
               order
               |> Ash.Changeset.for_update(:submit_contact_details, %{
                 customer_name: "New Customer",
                 customer_email: "newcustomer@example.com"
               })
               |> Ash.update(authorize?: false)

      assert {:ok, user} = Accounts.get_user_by_email("newcustomer@example.com", authorize?: false)
      assert user.name == "New Customer"
      assert to_string(user.email) == "newcustomer@example.com"

      assert order.user_id == user.id
    end

    test "updates existing user name when email already exists" do
      alias Edenflowers.Accounts.User

      {:ok, existing_user} = Edenflowers.Accounts.upsert_user("existing@example.com", "Old Name", authorize?: false)
      assert existing_user.name == "Old Name"

      order = Orders.create_for_checkout!(authorize?: false)

      assert {:ok, order} =
               order
               |> Ash.Changeset.for_update(:submit_contact_details, %{
                 customer_name: "Updated Name",
                 customer_email: "existing@example.com"
               })
               |> Ash.update(authorize?: false)

      {:ok, updated_user} = Accounts.get_user_by_email("existing@example.com", authorize?: false)
      assert updated_user.name == "Updated Name"
      assert updated_user.id == existing_user.id

      assert order.user_id == existing_user.id
    end

    test "associates order with correct user when multiple orders for same customer" do
      alias Edenflowers.Accounts.User

      order1 = Orders.create_for_checkout!(authorize?: false)

      {:ok, order1} =
        order1
        |> Ash.Changeset.for_update(:submit_contact_details, %{
          customer_name: "Regular Customer",
          customer_email: "regular@example.com"
        })
        |> Ash.update(authorize?: false)

      order2 = Orders.create_for_checkout!(authorize?: false)

      {:ok, order2} =
        order2
        |> Ash.Changeset.for_update(:submit_contact_details, %{
          customer_name: "Regular Customer",
          customer_email: "regular@example.com"
        })
        |> Ash.update(authorize?: false)

      assert order1.user_id == order2.user_id

      {:ok, user} = Accounts.get_user_by_email("regular@example.com", authorize?: false)
      assert user.id == order1.user_id
    end

    test "handles case-insensitive email matching" do
      alias Edenflowers.Accounts.User

      {:ok, user1} = Edenflowers.Accounts.upsert_user("customer@example.com", "Customer", authorize?: false)

      order = Orders.create_for_checkout!(authorize?: false)

      {:ok, order} =
        order
        |> Ash.Changeset.for_update(:submit_contact_details, %{
          customer_name: "Customer",
          customer_email: "CUSTOMER@EXAMPLE.COM"
        })
        |> Ash.update(authorize?: false)

      # Should match existing user (ci_string field)
      assert order.user_id == user1.id

      all_users = Ash.read!(User, authorize?: false)
      matching_users = Enum.filter(all_users, fn u -> to_string(u.email) == "customer@example.com" end)
      assert length(matching_users) == 1
    end

    test "preserves user_id through subsequent step updates" do
      alias Edenflowers.Accounts.User

      order = Orders.create_for_checkout!(authorize?: false)

      {:ok, order} =
        order
        |> Ash.Changeset.for_update(:submit_contact_details, %{
          customer_name: "Test User",
          customer_email: "test@example.com"
        })
        |> Ash.update(authorize?: false)

      original_user_id = order.user_id
      {:ok, user} = Accounts.get_user_by_email("test@example.com", authorize?: false)
      assert original_user_id == user.id

      {:ok, order} =
        order
        |> Ash.Changeset.for_update(:submit_gift_options, %{gift: false})
        |> Ash.update(authorize?: false)

      assert order.user_id == original_user_id
    end

    test "allows nil customer_name but requires customer_email" do
      alias Edenflowers.Accounts.User

      order = Orders.create_for_checkout!(authorize?: false)

      assert {:ok, order} =
               order
               |> Ash.Changeset.for_update(:submit_contact_details, %{
                 customer_email: "nametest@example.com"
               })
               |> Ash.update(authorize?: false)

      {:ok, user} = Accounts.get_user_by_email("nametest@example.com", authorize?: false)
      assert is_nil(user.name)
      assert order.user_id == user.id

      order2 = Orders.create_for_checkout!(authorize?: false)

      assert {:error, error} =
               order2
               |> Ash.Changeset.for_update(:submit_contact_details, %{
                 customer_name: "Test User"
               })
               |> Ash.update(authorize?: false)

      assert %Ash.Error.Invalid{} = error
    end
  end

  describe "Newsletter opt-in during checkout" do
    alias Edenflowers.Accounts.User
    alias Edenflowers.Pricing.Workers.SendNewsletterPromoEmail

    test "checkbox checked subscribes the user, stamps the order, and enqueues the welcome email worker" do
      order = Orders.create_for_checkout!(authorize?: false)

      assert {:ok, updated_order} =
               order
               |> Ash.Changeset.for_update(:submit_contact_details, %{
                 customer_name: "Subscriber",
                 customer_email: "subscriber@example.com",
                 newsletter_opt_in: true
               })
               |> Ash.update(authorize?: false)

      assert updated_order.newsletter_offer_hidden? == true

      {:ok, user} = Accounts.get_user_by_email("subscriber@example.com", authorize?: false)
      assert user.newsletter_opt_in == true

      assert_enqueued(
        worker: SendNewsletterPromoEmail,
        args: %{"email" => "subscriber@example.com", "locale" => order.locale}
      )
    end

    test "checkbox unchecked leaves newsletter_opt_in false, the order unstamped, and enqueues no job" do
      order = Orders.create_for_checkout!(authorize?: false)

      assert {:ok, updated_order} =
               order
               |> Ash.Changeset.for_update(:submit_contact_details, %{
                 customer_name: "Bystander",
                 customer_email: "bystander@example.com",
                 newsletter_opt_in: false
               })
               |> Ash.update(authorize?: false)

      assert updated_order.newsletter_offer_hidden? == false

      {:ok, user} = Accounts.get_user_by_email("bystander@example.com", authorize?: false)
      assert user.newsletter_opt_in == false

      refute_enqueued(worker: SendNewsletterPromoEmail)
    end

    test "an already-subscribed user hides the offer even when the box is left unticked" do
      Ash.Seed.seed!(User, %{name: "Existing", email: "existing@example.com", newsletter_opt_in: true})
      order = Orders.create_for_checkout!(authorize?: false)

      assert {:ok, updated_order} =
               order
               |> Ash.Changeset.for_update(:submit_contact_details, %{
                 customer_name: "Existing",
                 customer_email: "existing@example.com",
                 newsletter_opt_in: false
               })
               |> Ash.update(authorize?: false)

      assert updated_order.newsletter_offer_hidden? == true
    end

    # A legacy user row can have a NULL newsletter_opt_in. The stamp computes
    # `user.newsletter_subscribed? || user.newsletter_promo_used?`; the first
    # calc resolves to nil there, so this guards that `||` handles nil without
    # crashing (unlike the Ash `not` that crashed the original template).
    test "a user with a null newsletter_opt_in stamps the order without crashing" do
      user = Ash.Seed.seed!(User, %{name: "Legacy", email: "legacy@example.com"})

      {:ok, _} =
        Ecto.Adapters.SQL.query(
          Edenflowers.Repo,
          "UPDATE users SET newsletter_opt_in = NULL WHERE id = $1",
          [Ecto.UUID.dump!(user.id)]
        )

      order = Orders.create_for_checkout!(authorize?: false)

      assert {:ok, updated_order} =
               order
               |> Ash.Changeset.for_update(:submit_contact_details, %{
                 customer_name: "Legacy",
                 customer_email: "legacy@example.com",
                 newsletter_opt_in: false
               })
               |> Ash.update(authorize?: false)

      assert updated_order.newsletter_offer_hidden? == false
    end

    test "omitting the argument defaults to no opt-in" do
      order = Orders.create_for_checkout!(authorize?: false)

      assert {:ok, _order} =
               order
               |> Ash.Changeset.for_update(:submit_contact_details, %{
                 customer_name: "Default",
                 customer_email: "default@example.com"
               })
               |> Ash.update(authorize?: false)

      {:ok, user} = Accounts.get_user_by_email("default@example.com", authorize?: false)
      assert user.newsletter_opt_in == false

      refute_enqueued(worker: SendNewsletterPromoEmail)
    end
  end

  describe "Promotion minimum cart total validation" do
    test "applies promotion when cart total meets minimum requirement" do
      tax_rate = generate(tax_rate(percentage: "0.255"))
      product = generate(product(tax_rate_id: tax_rate.id))
      product_variant = generate(product_variant(product_id: product.id, price: "25.00"))

      promotion = generate(promotion(discount_rate: "0.20", minimum_cart_total: "40.00"))

      order = Orders.create_for_checkout!(authorize?: false)

      generate(
        line_item(
          order_id: order.id,
          product_variant_id: product_variant.id,
          quantity: 2
        )
      )

      assert {:ok, order} =
               Orders.add_promotion_with_id(order, promotion.id, authorize?: false, load: [:items_subtotal])

      assert order.promotion_id == promotion.id
      # After 20% discount: 50.00 - 10.00 = 40.00
      assert Decimal.equal?(order.items_subtotal, "40.00")
    end

    test "rejects promotion when cart total is below minimum requirement" do
      tax_rate = generate(tax_rate(percentage: "0.255"))
      product = generate(product(tax_rate_id: tax_rate.id))
      product_variant = generate(product_variant(product_id: product.id, price: "15.00"))

      promotion = generate(promotion(discount_rate: "0.20", minimum_cart_total: "50.00"))

      order = Orders.create_for_checkout!(authorize?: false)

      generate(
        line_item(
          order_id: order.id,
          product_variant_id: product_variant.id,
          quantity: 2
        )
      )

      assert {:error, error} = Orders.add_promotion_with_id(order, promotion.id, authorize?: false)
      assert %Ash.Error.Invalid{} = error
    end

    test "applies promotion when cart total exactly meets minimum requirement" do
      tax_rate = generate(tax_rate(percentage: "0.10"))
      product = generate(product(tax_rate_id: tax_rate.id))
      product_variant = generate(product_variant(product_id: product.id, price: "50.00"))

      promotion = generate(promotion(discount_rate: "0.15", minimum_cart_total: "50.00"))

      order = Orders.create_for_checkout!(authorize?: false)

      generate(
        line_item(
          order_id: order.id,
          product_variant_id: product_variant.id,
          quantity: 1
        )
      )

      assert {:ok, order} =
               Orders.add_promotion_with_id(order, promotion.id, authorize?: false, load: [:items_subtotal])

      assert order.promotion_id == promotion.id
      # After 15% discount: 50.00 - 7.50 = 42.50
      assert Decimal.equal?(order.items_subtotal, "42.50")
    end

    test "rejects promotion when cart is empty" do
      promotion = generate(promotion(discount_rate: "0.10", minimum_cart_total: "20.00"))

      order = Orders.create_for_checkout!(authorize?: false)

      assert {:error, error} = Orders.add_promotion_with_id(order, promotion.id, authorize?: false)
      assert %Ash.Error.Invalid{} = error
    end

    test "applies promotion with 0 minimum cart total to any order" do
      tax_rate = generate(tax_rate(percentage: "0.10"))
      product = generate(product(tax_rate_id: tax_rate.id))
      product_variant = generate(product_variant(product_id: product.id, price: "5.00"))

      promotion = generate(promotion(discount_rate: "0.10", minimum_cart_total: "0"))

      order = Orders.create_for_checkout!(authorize?: false)

      generate(
        line_item(
          order_id: order.id,
          product_variant_id: product_variant.id,
          quantity: 1
        )
      )

      assert {:ok, order} = Orders.add_promotion_with_id(order, promotion.id, authorize?: false)
      assert order.promotion_id == promotion.id
    end
  end

  describe "Order Step 3 - Fulfillment and delivery" do
    setup do
      tax_rate = generate(tax_rate())

      pickup_option =
        generate(
          fulfillment_option(
            tax_rate_id: tax_rate.id,
            name: "Store Pickup",
            fulfillment_method: :pickup,
            rate_type: :fixed,
            base_price: "5.00",
            same_day: true,
            order_deadline: ~T[15:00:00]
          )
        )

      delivery_fixed =
        generate(
          fulfillment_option(
            tax_rate_id: tax_rate.id,
            name: "Delivery - Fixed",
            fulfillment_method: :delivery,
            rate_type: :fixed,
            base_price: "10.00",
            same_day: false,
            order_deadline: ~T[12:00:00]
          )
        )

      delivery_dynamic =
        generate(
          fulfillment_option(
            tax_rate_id: tax_rate.id,
            name: "Delivery - Dynamic",
            fulfillment_method: :delivery,
            rate_type: :dynamic,
            base_price: "5.00",
            price_per_km: "2.00",
            free_dist_km: 3,
            max_dist_km: 15,
            same_day: true,
            order_deadline: ~T[14:00:00]
          )
        )

      %{
        tax_rate: tax_rate,
        pickup_option: pickup_option,
        delivery_fixed: delivery_fixed,
        delivery_dynamic: delivery_dynamic
      }
    end

    test "save_step_3 requires fulfillment_date", %{pickup_option: pickup_option} do
      order = generate(order(state: :delivery))

      assert {:error, error} =
               order
               |> Ash.Changeset.for_update(:submit_delivery, %{
                 fulfillment_option_id: pickup_option.id
               })
               |> Ash.update(authorize?: false)

      assert %Ash.Error.Invalid{} = error
    end

    test "save_step_3 with pickup clears delivery fields", %{pickup_option: pickup_option} do
      order = generate(order(state: :delivery))

      # Note: In real flow, delivery_address would trigger HereAPI calls
      # For pickup, we don't need delivery address
      assert {:ok, order} =
               order
               |> Ash.Changeset.for_update(:submit_delivery, %{
                 fulfillment_option_id: pickup_option.id,
                 fulfillment_date: Date.add(Date.utc_today(), 1)
               })
               |> Ash.update(authorize?: false)

      assert order.fulfillment_option_id == pickup_option.id
      assert order.fulfillment_fee == Decimal.new("5.00")
      assert order.state == :payment

      assert is_nil(order.delivery_address)
      assert is_nil(order.geocoded_address)
      assert is_nil(order.here_id)
      assert is_nil(order.distance)
      assert is_nil(order.position)
    end

    test "save_step_3 with pickup calculates correct fixed price", %{pickup_option: pickup_option} do
      order = generate(order(state: :delivery))

      assert {:ok, order} =
               order
               |> Ash.Changeset.for_update(:submit_delivery, %{
                 fulfillment_option_id: pickup_option.id,
                 fulfillment_date: Date.add(Date.utc_today(), 2)
               })
               |> Ash.update(authorize?: false)

      assert Decimal.equal?(order.fulfillment_fee, "5.00")
    end

    test "save_step_3 validates fulfillment_date is not in the past", %{pickup_option: pickup_option} do
      order = generate(order(state: :delivery))

      yesterday = Date.add(Date.utc_today(), -1)

      assert {:error, error} =
               order
               |> Ash.Changeset.for_update(:submit_delivery, %{
                 fulfillment_option_id: pickup_option.id,
                 fulfillment_date: yesterday
               })
               |> Ash.update(authorize?: false)

      assert %Ash.Error.Invalid{} = error
    end

    test "save_step_3 rejects a date the option no longer allows", %{pickup_option: pickup_option} do
      order = generate(order(state: :delivery))
      closed_date = Date.add(Date.utc_today(), 3)

      {:ok, _} =
        Edenflowers.Fulfillment.update_calendar(
          pickup_option,
          %{disabled_dates: [closed_date]},
          authorize?: false
        )

      assert {:error, error} =
               order
               |> Ash.Changeset.for_update(:submit_delivery, %{
                 fulfillment_option_id: pickup_option.id,
                 fulfillment_date: closed_date
               })
               |> Ash.update(authorize?: false)

      assert %Ash.Error.Invalid{} = error
    end
  end

  describe "Order state transitions" do
    test "finalize_checkout requires payment_intent_id" do
      order = generate(order(payment_intent_id: nil))

      assert {:error, error} = Orders.finalize_checkout(order.id, authorize?: false)
      assert %Ash.Error.Invalid{} = error
    end

    test "payment_status transitions from pending to paid" do
      order = generate(order(state: :payment, payment_status: :pending, payment_intent_id: "pi_test"))

      assert {:ok, order} = Orders.finalize_checkout(order.id, authorize?: false)
      assert order.payment_status == :paid
    end

    test "cannot finalize order already in :order state" do
      order = generate(order(state: :placed, payment_status: :paid, payment_intent_id: "pi_test"))

      assert {:error, error} = Orders.finalize_checkout(order.id, authorize?: false)
      assert %Ash.Error.Invalid{} = error
    end
  end

  describe "Order reset action" do
    test "reset clears all checkout fields and returns to step 1" do
      tax_rate = generate(tax_rate())

      fulfillment_option =
        generate(
          fulfillment_option(
            tax_rate_id: tax_rate.id,
            name: "Pickup",
            fulfillment_method: :pickup,
            rate_type: :fixed,
            base_price: "5.00"
          )
        )

      promotion = generate(promotion(minimum_cart_total: "0"))

      order =
        generate(
          order(
            state: :payment,
            customer_name: "Test Customer",
            customer_email: "test@example.com",
            gift: true,
            recipient_name: "Recipient",
            card_message: "With love",
            recipient_phone_number: "+358401234567",
            delivery_address: "Test Address",
            delivery_instructions: "Ring twice",
            fulfillment_date: Date.add(Date.utc_today(), 1),
            fulfillment_fee: "5.00",
            geocoded_address: "Calculated Address",
            here_id: "here123",
            distance: 5000,
            position: "60.1699,24.9384",
            payment_intent_id: "pi_test123",
            promotion_id: promotion.id,
            fulfillment_option_id: fulfillment_option.id,
            newsletter_offer_hidden?: true
          )
        )

      assert {:ok, reset_order} = Orders.restart_checkout(order, authorize?: false)

      assert reset_order.state == :contact_details
      assert is_nil(reset_order.customer_name)
      assert is_nil(reset_order.customer_email)
      assert reset_order.gift == false
      assert is_nil(reset_order.recipient_name)
      assert is_nil(reset_order.card_message)
      assert is_nil(reset_order.recipient_phone_number)
      assert is_nil(reset_order.delivery_address)
      assert is_nil(reset_order.delivery_instructions)
      assert is_nil(reset_order.fulfillment_date)
      assert is_nil(reset_order.fulfillment_fee)
      assert is_nil(reset_order.geocoded_address)
      assert is_nil(reset_order.here_id)
      assert is_nil(reset_order.distance)
      assert is_nil(reset_order.position)
      assert is_nil(reset_order.payment_intent_id)
      assert is_nil(reset_order.promotion_id)
      assert is_nil(reset_order.fulfillment_option_id)
      assert reset_order.newsletter_offer_hidden? == false
    end

    test "reset preserves order id and returns the order to :contact_details" do
      order = generate(order(state: :delivery, customer_name: "Test", customer_email: "test@example.com"))
      original_id = order.id

      assert {:ok, reset_order} = Orders.restart_checkout(order, authorize?: false)

      # The same row, rewound to the start of the flow
      assert reset_order.id == original_id
      assert reset_order.state == :contact_details
    end

    test "reset destroys all line items, including any leftover card" do
      tax_rate = generate(tax_rate())
      product = generate(product(tax_rate_id: tax_rate.id))
      variant = generate(product_variant(product_id: product.id))

      cards_category = generate(product_category(slug: "cards"))
      card_product = generate(product(product_category_id: cards_category.id, tax_rate_id: tax_rate.id))

      order = gift_order_with_card(card_product, :medium)
      generate(line_item(order_id: order.id, product_variant_id: variant.id, quantity: 2))

      order = Ash.load!(order, [:line_items], authorize?: false)
      assert length(order.line_items) == 2

      assert {:ok, reset_order} = Orders.restart_checkout(order, authorize?: false)
      reset_order = Ash.load!(reset_order, [:line_items, :cart_effectively_empty?], authorize?: false)

      assert reset_order.line_items == []
      assert reset_order.cart_effectively_empty? == true
    end
  end

  describe "Orders.remove_line_item action" do
    test "removes a single line item without resetting checkout when others remain" do
      tax_rate = generate(tax_rate())
      product = generate(product(tax_rate_id: tax_rate.id))
      variant_1 = generate(product_variant(product_id: product.id))
      variant_2 = generate(product_variant(product_id: product.id))

      order =
        generate(
          order(
            state: :delivery,
            customer_name: "Keep Me",
            customer_email: "keep@example.com"
          )
        )

      to_remove = generate(line_item(order_id: order.id, product_variant_id: variant_1.id, quantity: 1))
      _keep = generate(line_item(order_id: order.id, product_variant_id: variant_2.id, quantity: 1))

      assert {:ok, updated} = Orders.remove_line_item(order, to_remove.id, authorize?: false)

      assert updated.state == :delivery
      assert updated.customer_name == "Keep Me"
      assert length(updated.line_items) == 1
    end

    test "removing the last non-card line item resets checkout fields" do
      tax_rate = generate(tax_rate())
      product = generate(product(tax_rate_id: tax_rate.id))
      variant = generate(product_variant(product_id: product.id))

      order =
        generate(
          order(
            state: :payment,
            customer_name: "Stale Customer",
            customer_email: "stale@example.com",
            recipient_name: "Recipient",
            payment_intent_id: "pi_stale"
          )
        )

      line_item = generate(line_item(order_id: order.id, product_variant_id: variant.id, quantity: 1))

      assert {:ok, updated} = Orders.remove_line_item(order, line_item.id, authorize?: false)

      assert updated.state == :contact_details
      assert is_nil(updated.customer_name)
      assert is_nil(updated.customer_email)
      assert is_nil(updated.recipient_name)
      assert is_nil(updated.payment_intent_id)
      assert updated.line_items == []
    end

    test "broadcasts order:checkout_restarted when the cart empties" do
      tax_rate = generate(tax_rate())
      product = generate(product(tax_rate_id: tax_rate.id))
      variant = generate(product_variant(product_id: product.id))

      order = generate(order(state: :delivery, customer_name: "X", customer_email: "x@example.com"))
      line_item = generate(line_item(order_id: order.id, product_variant_id: variant.id, quantity: 1))

      Phoenix.PubSub.subscribe(Edenflowers.PubSub, "order:checkout_restarted:#{order.id}")

      assert {:ok, _} = Orders.remove_line_item(order, line_item.id, authorize?: false)

      assert_receive %Phoenix.Socket.Broadcast{topic: topic}
      assert topic == "order:checkout_restarted:#{order.id}"
    end

    test "does not broadcast order:checkout_restarted when other items remain" do
      tax_rate = generate(tax_rate())
      product = generate(product(tax_rate_id: tax_rate.id))
      variant_1 = generate(product_variant(product_id: product.id))
      variant_2 = generate(product_variant(product_id: product.id))

      order = generate(order(state: :delivery))
      to_remove = generate(line_item(order_id: order.id, product_variant_id: variant_1.id, quantity: 1))
      _keep = generate(line_item(order_id: order.id, product_variant_id: variant_2.id, quantity: 1))

      Phoenix.PubSub.subscribe(Edenflowers.PubSub, "order:checkout_restarted:#{order.id}")

      assert {:ok, _} = Orders.remove_line_item(order, to_remove.id, authorize?: false)

      refute_receive %Phoenix.Socket.Broadcast{topic: _}, 100
    end
  end

  describe "cart_effectively_empty? calculation" do
    test "true when the order has no line items" do
      order = Orders.create_for_checkout!(authorize?: false)
      order = Ash.load!(order, [:cart_effectively_empty?], authorize?: false)

      assert order.cart_effectively_empty? == true
    end

    test "true when the only remaining line item is a card" do
      tax_rate = generate(tax_rate())
      cards_category = generate(product_category(slug: "cards"))
      card_product = generate(product(product_category_id: cards_category.id, tax_rate_id: tax_rate.id))

      order = gift_order_with_card(card_product, :medium)
      order = Ash.load!(order, [:cart_effectively_empty?], authorize?: false)

      assert order.cart_effectively_empty? == true
    end

    test "false when at least one non-card line item remains" do
      tax_rate = generate(tax_rate())
      product = generate(product(tax_rate_id: tax_rate.id))
      variant = generate(product_variant(product_id: product.id))

      order = generate(order())
      generate(line_item(order_id: order.id, product_variant_id: variant.id, quantity: 1))

      order = Ash.load!(order, [:cart_effectively_empty?], authorize?: false)

      assert order.cart_effectively_empty? == false
    end
  end

  describe "Order update_locale action" do
    test "updates locale to a configured locale" do
      order = Orders.create_for_checkout!(authorize?: false)
      assert order.locale == "sv-FI"

      assert {:ok, updated_order} = Orders.update_locale(order, "en-GB", authorize?: false)
      assert updated_order.locale == "en-GB"
    end

    test "rejects locale that is not in the configured set" do
      order = Orders.create_for_checkout!(authorize?: false)

      assert {:error, error} = Orders.update_locale(order, "en-US", authorize?: false)
      assert %Ash.Error.Invalid{} = error
    end
  end

  describe "add_promotion_with_code argument validation" do
    test "rejects nil code" do
      order = generate(order())

      assert {:error, error} = Orders.add_promotion_with_code(order, nil, authorize?: false)
      assert %Ash.Error.Invalid{} = error
    end

    test "rejects whitespace-only code" do
      order = generate(order())

      assert {:error, error} = Orders.add_promotion_with_code(order, "   ", authorize?: false)
      assert %Ash.Error.Invalid{} = error
    end
  end

  describe "Card line items via Order" do
    setup do
      tax_rate = generate(tax_rate())
      cards_category = generate(product_category(slug: "cards", visibility: :public))

      card_product =
        generate(product(product_category_id: cards_category.id, tax_rate_id: tax_rate.id, draft: false))

      card_variant_a = generate(product_variant(product_id: card_product.id, size: :small, draft: false))
      card_variant_b = generate(product_variant(product_id: card_product.id, size: :large, draft: false))

      order = Orders.create_for_checkout!(authorize?: false)

      %{order: order, card_variant_a: card_variant_a, card_variant_b: card_variant_b}
    end

    test "add_card adds a card line item and returns the loaded order", %{
      order: order,
      card_variant_a: card_variant_a
    } do
      assert {:ok, order} = Orders.add_card(order, card_variant_a.id, authorize?: false)

      card = Enum.find(order.line_items, & &1.is_card)
      assert card
      assert card.product_variant_id == card_variant_a.id
      assert card.variant_size == card_variant_a.size

      # @checkout_load calculations should be present on the returned order
      refute match?(%Ash.NotLoaded{}, order.grand_total)
    end

    test "add_card replaces an existing card line item rather than appending", %{
      order: order,
      card_variant_a: card_variant_a,
      card_variant_b: card_variant_b
    } do
      {:ok, _} = Orders.add_card(order, card_variant_a.id, authorize?: false)
      assert {:ok, order} = Orders.add_card(order, card_variant_b.id, authorize?: false)

      cards = Enum.filter(order.line_items, & &1.is_card)
      assert length(cards) == 1
      assert hd(cards).product_variant_id == card_variant_b.id
      assert hd(cards).variant_size == card_variant_b.size
    end

    test "remove_card destroys the card line item and clears card_message", %{
      card_variant_a: card_variant_a
    } do
      gift_order = generate(order(state: :gift_options, gift: true))

      {:ok, with_card} = Orders.add_card(gift_order, card_variant_a.id, authorize?: false)

      with_message =
        with_card
        |> Ash.Changeset.for_update(:submit_gift_options, %{
          gift: true,
          recipient_name: "Jane",
          card_message: "Hello"
        })
        |> Ash.update!(authorize?: false)

      assert with_message.card_message == "Hello"

      assert {:ok, order} = Orders.remove_card(with_message, authorize?: false)

      refute Enum.any?(order.line_items, & &1.is_card)
      assert is_nil(order.card_message)
    end

    test "remove_card is a no-op when there is no card line item", %{order: order} do
      order = Orders.get_order_for_checkout!(order.id, authorize?: false)
      refute Enum.any?(order.line_items, & &1.is_card)

      assert {:ok, order} = Orders.remove_card(order, authorize?: false)
      refute Enum.any?(order.line_items, & &1.is_card)
    end
  end

  describe "add_payment_intent_id policy" do
    test "guest can attach payment intent during checkout" do
      order = generate(order(state: :payment))

      assert {:ok, updated} = Orders.add_payment_intent_id(order, "pi_guest_test", actor: nil)
      assert updated.payment_intent_id == "pi_guest_test"
    end

    test "system actor can attach payment intent during checkout" do
      order = generate(order(state: :payment))

      assert {:ok, updated} =
               Orders.add_payment_intent_id(order, "pi_system_test", actor: %{system: true})

      assert updated.payment_intent_id == "pi_system_test"
    end

    test "cannot attach payment intent to a placed order" do
      order = generate(order(state: :placed, payment_status: :paid, payment_intent_id: "pi_old"))

      assert {:error, error} = Orders.add_payment_intent_id(order, "pi_new", actor: nil)
      assert %Ash.Error.Forbidden{} = error
    end
  end

  describe "Config snapshots are frozen on placed orders" do
    # These tests simulate config drift by bypassing Ash and writing directly
    # via Ecto — the snapshot must hold even if config is edited that way.
    test "promotion discount_rate is snapshotted and immune to later edits" do
      tax_rate = generate(tax_rate())
      product = generate(product(tax_rate_id: tax_rate.id))
      variant = generate(product_variant(product_id: product.id, price: "100.00"))
      promotion = generate(promotion(discount_rate: "0.20", minimum_cart_total: "0"))

      order = Orders.create_for_checkout!(authorize?: false)

      generate(line_item(order_id: order.id, product_variant_id: variant.id, quantity: 1))

      {:ok, order} = Orders.add_promotion_with_id(order, promotion.id, authorize?: false)
      assert Decimal.equal?(order.discount_rate, Decimal.new("0.20"))

      Edenflowers.Repo.update_all(
        from(p in "promotions", where: p.id == ^Ecto.UUID.dump!(promotion.id)),
        set: [discount_rate: Decimal.new("0.99")]
      )

      order = Orders.get_order_for_checkout!(order.id, authorize?: false)
      assert Decimal.equal?(order.discount_rate, Decimal.new("0.20"))

      [line_item] = order.line_items
      line_item = Ash.load!(line_item, [:discount], authorize?: false)
      assert Decimal.equal?(line_item.discount, Decimal.new("20.00"))
    end

    test "clearing the promotion clears the snapshotted percentage" do
      promotion = generate(promotion(discount_rate: "0.20", minimum_cart_total: "0"))
      order = Orders.create_for_checkout!(authorize?: false)

      {:ok, order} = Orders.add_promotion_with_id(order, promotion.id, authorize?: false)
      assert Decimal.equal?(order.discount_rate, Decimal.new("0.20"))

      {:ok, order} = Orders.clear_promotion(order, authorize?: false)
      assert is_nil(order.discount_rate)
    end

    test "fulfillment_tax_percentage is snapshotted and immune to later edits" do
      tax_rate = generate(tax_rate(percentage: "0.10"))

      option =
        generate(
          fulfillment_option(
            fulfillment_method: :pickup,
            rate_type: :fixed,
            base_price: "10.00",
            tax_rate_id: tax_rate.id
          )
        )

      order = Orders.create_for_checkout!(authorize?: false)

      {:ok, order} = Orders.update_fulfillment_option(order, option.id, authorize?: false)
      assert Decimal.equal?(order.fulfillment_tax_percentage, Decimal.new("0.10"))

      Edenflowers.Repo.update_all(
        from(t in "tax_rates", where: t.id == ^Ecto.UUID.dump!(tax_rate.id)),
        set: [percentage: Decimal.new("0.25")]
      )

      order = Orders.get_order_for_checkout!(order.id, authorize?: false)
      assert Decimal.equal?(order.fulfillment_tax_percentage, Decimal.new("0.10"))
    end

    test "promotion name and code are snapshotted and immune to later edits" do
      promotion =
        generate(
          promotion(
            name: "Spring Sale",
            code: "SPRING20",
            discount_rate: "0.20",
            minimum_cart_total: "0"
          )
        )

      order = Orders.create_for_checkout!(authorize?: false)
      {:ok, order} = Orders.add_promotion_with_id(order, promotion.id, authorize?: false)

      assert order.promotion_name == "Spring Sale"
      assert order.promotion_code == "SPRING20"

      Edenflowers.Repo.update_all(
        from(p in "promotions", where: p.id == ^Ecto.UUID.dump!(promotion.id)),
        set: [name: "Renamed", code: "RENAMED"]
      )

      order = Orders.get_order_for_checkout!(order.id, authorize?: false)
      assert order.promotion_name == "Spring Sale"
      assert order.promotion_code == "SPRING20"
    end

    test "fulfillment option name is snapshotted and immune to later edits" do
      tax_rate = generate(tax_rate(percentage: "0.10"))

      option =
        generate(
          fulfillment_option(
            name: "Pickup at Studio",
            fulfillment_method: :pickup,
            rate_type: :fixed,
            base_price: "5.00",
            tax_rate_id: tax_rate.id
          )
        )

      order = Orders.create_for_checkout!(authorize?: false)
      {:ok, order} = Orders.update_fulfillment_option(order, option.id, authorize?: false)

      assert order.fulfillment_option_name == "Pickup at Studio"

      Edenflowers.Repo.update_all(
        from(o in "fulfillment_options", where: o.id == ^Ecto.UUID.dump!(option.id)),
        set: [name: "Renamed Option"]
      )

      order = Orders.get_order_for_checkout!(order.id, authorize?: false)
      assert order.fulfillment_option_name == "Pickup at Studio"
    end

    test "changing the fulfillment option re-snapshots method and tax percentage" do
      vat_low = generate(tax_rate(percentage: "0.10"))
      vat_high = generate(tax_rate(percentage: "0.25"))

      pickup =
        generate(
          fulfillment_option(
            fulfillment_method: :pickup,
            rate_type: :fixed,
            base_price: "5.00",
            tax_rate_id: vat_low.id
          )
        )

      delivery =
        generate(
          fulfillment_option(
            fulfillment_method: :delivery,
            rate_type: :fixed,
            base_price: "15.00",
            tax_rate_id: vat_high.id
          )
        )

      order = Orders.create_for_checkout!(authorize?: false)

      {:ok, order} = Orders.update_fulfillment_option(order, pickup.id, authorize?: false)
      assert order.fulfillment_method == :pickup
      assert Decimal.equal?(order.fulfillment_tax_percentage, Decimal.new("0.10"))

      {:ok, order} = Orders.update_fulfillment_option(order, delivery.id, authorize?: false)
      assert order.fulfillment_method == :delivery
      assert Decimal.equal?(order.fulfillment_tax_percentage, Decimal.new("0.25"))
    end
  end
end
