defmodule Edenflowers.Pricing.PromotionTest do
  use Edenflowers.DataCase, async: true

  alias Edenflowers.Orders
  alias Edenflowers.Pricing
  alias Edenflowers.Pricing.Promotion

  describe "Promotion Resource" do
    test "gets promotion using a mixed-case code with surrounding whitespace" do
      Promotion
      |> Ash.Changeset.for_create(:create, %{
        name: "A promotion",
        code: "CHRISTMAS20",
        discount_rate: "0.20",
        minimum_cart_total: "30.00",
        start_date: ~D[2024-12-19]
      })
      |> Ash.create!(authorize?: false)

      assert {:ok, %Promotion{}} =
               Pricing.get_promotion_by_code(" Christmas20 ", ~D[2024-12-20])
    end

    test "fails to get promotion if code doesn't match" do
      Promotion
      |> Ash.Changeset.for_create(:create, %{
        name: "A promotion",
        code: "CHRISTMAS20",
        discount_rate: "0.20",
        minimum_cart_total: "30.00",
        start_date: ~D[2024-12-19]
      })
      |> Ash.create!(authorize?: false)

      assert {:error, %Ash.Error.Invalid{}} = Pricing.get_promotion_by_code("AUTUMN20", ~D[2024-12-20])
    end

    test "fails to get promotion if current date is before start date" do
      Promotion
      |> Ash.Changeset.for_create(:create, %{
        name: "A promotion",
        code: "CHRISTMAS20",
        discount_rate: "0.20",
        minimum_cart_total: "30.00",
        start_date: ~D[2024-12-19]
      })
      |> Ash.create!(authorize?: false)

      assert {:error, %Ash.Error.Invalid{}} = Pricing.get_promotion_by_code("CHRISTMAS20", ~D[2024-12-18])
    end

    test "gets promotion if current date is same as start date" do
      Promotion
      |> Ash.Changeset.for_create(:create, %{
        name: "A promotion",
        code: "CHRISTMAS20",
        discount_rate: "0.20",
        minimum_cart_total: "30.00",
        start_date: ~D[2024-12-19]
      })
      |> Ash.create!(authorize?: false)

      assert {:ok, %Promotion{}} =
               Pricing.get_promotion_by_code("CHRISTMAS20", ~D[2024-12-19])
    end

    test "gets promotion if current date is after start date and on expiration date" do
      Promotion
      |> Ash.Changeset.for_create(:create, %{
        name: "A promotion",
        code: "CHRISTMAS20",
        discount_rate: "0.20",
        minimum_cart_total: "30.00",
        start_date: ~D[2024-12-19],
        expiration_date: ~D[2024-12-22]
      })
      |> Ash.create!(authorize?: false)

      assert {:ok, %Promotion{}} =
               Pricing.get_promotion_by_code("CHRISTMAS20", ~D[2024-12-22])
    end

    test "fails to get promotion if current date is after expiration date" do
      Promotion
      |> Ash.Changeset.for_create(:create, %{
        name: "A promotion",
        code: "CHRISTMAS20",
        discount_rate: "0.20",
        minimum_cart_total: "30.00",
        start_date: ~D[2024-12-19],
        expiration_date: ~D[2024-12-22]
      })
      |> Ash.create!(authorize?: false)

      assert {:error, %Ash.Error.Invalid{}} = Pricing.get_promotion_by_code("CHRISTMAS20", ~D[2024-12-23])
    end
  end

  describe "newsletter welcome codes" do
    test "are 15% until Jennie sets the welcome offer" do
      {:ok, promo} = Pricing.create_newsletter_promotion(authorize?: false)

      assert Decimal.equal?(promo.discount_rate, "0.15")
      assert promo.usage_limit == 1
      assert promo.expiration_date == Date.add(Edenflowers.ShopTime.today(), 30)
    end

    test "take the welcome offer set at signup, and codes already sent keep their rate" do
      {:ok, before_change} = Pricing.create_newsletter_promotion(authorize?: false)

      Pricing.get_welcome_offer!()
      |> Pricing.update_welcome_offer!(%{discount_rate: "0.25"}, authorize?: false)

      {:ok, after_change} = Pricing.create_newsletter_promotion(authorize?: false)

      assert Decimal.equal?(after_change.discount_rate, "0.25")
      assert Decimal.equal?(Ash.reload!(before_change, authorize?: false).discount_rate, "0.15")
    end

    test "only an admin can change the welcome offer" do
      assert {:error, %Ash.Error.Forbidden{}} =
               Pricing.update_welcome_offer(Pricing.get_welcome_offer!(), %{discount_rate: "0.5"})
    end
  end

  describe "pass-it-on batches" do
    test "make distinct one-use 15% codes that work on any cart, under the batch name" do
      codes = Pricing.create_pass_it_on_batch!("Skicka vidare 2026-11", 3, actor: Edenflowers.Actors.system_actor())

      assert length(Enum.uniq(codes)) == 3

      for code <- codes do
        promotion = Pricing.get_promotion_by_code!(code)
        assert promotion.name == "Skicka vidare 2026-11"
        assert Decimal.equal?(promotion.discount_rate, "0.15")
        assert Decimal.equal?(promotion.minimum_cart_total, 0)
        assert promotion.usage_limit == 1
      end
    end

    test "can't be made by a customer" do
      assert {:error, %Ash.Error.Forbidden{}} = Pricing.create_pass_it_on_batch("Skicka vidare", 1, actor: nil)
    end
  end

  describe "Promotion usage tracking" do
    import Generator

    test "counts placed orders only" do
      promotion = generate(promotion())
      use_promotion(promotion, 2)
      generate(order(state: :payment, promotion_id: promotion.id))

      assert Ash.load!(promotion, :usage).usage == 2
    end

    test "counts an order once it is finalized with the promotion" do
      tax_rate = generate(tax_rate())
      product = generate(product(tax_rate_id: tax_rate.id))
      product_variant = generate(product_variant(product_id: product.id))
      promotion = generate(promotion(minimum_cart_total: "0"))

      order =
        generate(
          order(
            state: :payment,
            promotion_id: promotion.id,
            discount_rate: promotion.discount_rate,
            payment_intent_id: "pi_test"
          )
        )

      generate(line_item(order_id: order.id, product_variant_id: product_variant.id))

      order = Ash.load!(order, :grand_total, authorize?: false)
      assert Ash.load!(promotion, :usage).usage == 0

      {:ok, _order} =
        Orders.finalize_checkout(order.id, order.payment_intent_id, %{amount_paid: order.grand_total},
          authorize?: false
        )

      assert Ash.load!(promotion, :usage).usage == 1
    end
  end

  describe "Promotion usage limits" do
    import Generator

    defp limited_promotion(code, usage_limit) do
      Promotion
      |> Ash.Changeset.for_create(:create, %{
        name: "Limited #{code}",
        code: code,
        discount_rate: "0.10",
        minimum_cart_total: "0",
        usage_limit: usage_limit
      })
      |> Ash.create!(authorize?: false)
    end

    test "rejects promotion code when usage equals usage_limit" do
      promotion = limited_promotion("LIMITED", 5)
      use_promotion(promotion, 5)

      assert {:error, %Ash.Error.Invalid{}} = Pricing.get_promotion_by_code("LIMITED", Edenflowers.ShopTime.today())
    end

    test "allows promotion code when usage is below usage_limit" do
      promotion = limited_promotion("LIMITED10", 5)
      use_promotion(promotion, 4)

      assert {:ok, %Promotion{id: id}} = Pricing.get_promotion_by_code("LIMITED10", Edenflowers.ShopTime.today())
      assert id == promotion.id
    end

    test "counts usage for a guest, who can't read other people's orders" do
      promotion = limited_promotion("GUESTLIMIT", 1)
      use_promotion(promotion)

      assert {:error, %Ash.Error.Invalid{}} =
               Pricing.get_promotion_by_code("GUESTLIMIT", Edenflowers.ShopTime.today(), actor: nil)
    end

    test "allows unlimited usage when usage_limit is nil" do
      promotion = limited_promotion("UNLIMITED", nil)
      use_promotion(promotion, 20)

      assert {:ok, %Promotion{id: id}} = Pricing.get_promotion_by_code("UNLIMITED", Edenflowers.ShopTime.today())
      assert id == promotion.id
    end

    test "prevents applying promotion to order when usage limit reached" do
      tax_rate = generate(tax_rate())
      product = generate(product(tax_rate_id: tax_rate.id))
      product_variant = generate(product_variant(product_id: product.id, price: "30.00"))

      promotion = limited_promotion("MAXED", 10)
      use_promotion(promotion, 10)

      order = Orders.create_for_checkout!(authorize?: false)
      generate(line_item(order_id: order.id, product_variant_id: product_variant.id))

      assert {:error, %Ash.Error.Invalid{}} = Orders.add_promotion_with_code(order, "MAXED", authorize?: false)
    end
  end

  describe "a pass-it-on code's 30 days" do
    import Generator

    setup do
      [code] = Pricing.create_pass_it_on_batch!("Skicka vidare", 1, actor: Edenflowers.Actors.system_actor())
      {:ok, promotion} = Pricing.get_promotion_by_code(code)
      %{code: code, promotion: promotion}
    end

    test "start at the first customer scan and don't move after", %{promotion: promotion} do
      assert is_nil(promotion.expiration_date)

      promotion = Pricing.start_promotion_validity!(promotion, %{today: ~D[2026-11-05]}, actor: nil)
      assert promotion.expiration_date == ~D[2026-12-05]

      promotion = Pricing.start_promotion_validity!(promotion, %{today: ~D[2026-11-20]}, actor: nil)
      assert promotion.expiration_date == ~D[2026-12-05]

      assert {:error, _expired} = Pricing.get_promotion_by_code(promotion.code, ~D[2026-12-06])
    end

    test "card status keeps the last valid day inclusive and used cards traceable after expiry", %{promotion: card} do
      card = Pricing.start_promotion_validity!(card, %{today: ~D[2026-11-01]}, actor: nil)
      status = fn today -> Ash.load!(card, [card_status: [today: today]], authorize?: false).card_status end
      assert status.(~D[2026-12-01]) == :opened
      assert status.(~D[2026-12-02]) == :expired

      redeemed = Generator.placed_order(promotion_id: card.id)
      assert status.(~D[2026-12-02]) == :used

      Ash.Seed.update!(redeemed, %{fulfillment_status: :cancelled})
      assert status.(~D[2026-12-02]) == :expired
    end

    test "don't start when an admin opens the card", %{promotion: promotion} do
      promotion = Pricing.start_promotion_validity!(promotion, actor: generate(admin_user()))
      assert is_nil(promotion.expiration_date)
    end

    test "start when a customer applies the code", %{code: code, promotion: promotion} do
      order = Orders.create_for_checkout!(authorize?: false)
      Orders.add_promotion_from_link!(order, code, actor: nil)

      assert Ash.reload!(promotion, authorize?: false).expiration_date ==
               Date.add(Edenflowers.ShopTime.today(), 30)
    end

    test "start again after Jennie marks an opened card as not opened, unless it was used", %{promotion: card} do
      admin = generate(admin_user())
      assert {:error, _not_opened} = Pricing.mark_card_not_opened(card, actor: admin)

      card = Pricing.start_promotion_validity!(card, %{today: ~D[2026-11-01]}, actor: nil)
      assert {:error, _forbidden} = Pricing.mark_card_not_opened(card, actor: nil)

      card = Pricing.mark_card_not_opened!(card, actor: admin)
      assert is_nil(card.expiration_date)

      card = Pricing.start_promotion_validity!(card, %{today: ~D[2026-11-20]}, actor: nil)
      assert card.expiration_date == ~D[2026-12-20]

      Generator.placed_order(promotion_id: card.id)
      assert {:error, _used} = Pricing.mark_card_not_opened(card, actor: admin)
    end

    test "leave other codes' dates alone" do
      manual = generate(promotion(code: "MANUAL1"))
      assert Pricing.start_promotion_validity!(manual, actor: nil).expiration_date == manual.expiration_date
    end
  end

  describe "linking a pass-it-on card to its gift order" do
    import Generator

    setup do
      [code, other_code] =
        Pricing.create_pass_it_on_batch!("Skicka vidare", 2, actor: Edenflowers.Actors.system_actor())

      {:ok, card} = Pricing.get_promotion_by_code(code)
      {:ok, other_card} = Pricing.get_promotion_by_code(other_code)
      %{card: card, other_card: other_card, admin: generate(admin_user())}
    end

    test "can be re-picked until the recipient opens the card", %{card: card, admin: admin} do
      wrong = placed_order(gift: true, recipient_name: "Anna Virtanen")
      right = placed_order(gift: true, recipient_name: "Bea Berg")

      card = Pricing.link_card_to_gift_order!(card, wrong.id, actor: admin)
      card = Pricing.link_card_to_gift_order!(card, nil, actor: admin)
      card = Pricing.link_card_to_gift_order!(card, right.id, actor: admin, load: :recipient_first_name)
      assert card.recipient_first_name == "Bea"

      card = Pricing.start_promotion_validity!(card, actor: nil)
      assert {:error, _opened} = Pricing.link_card_to_gift_order(card, wrong.id, actor: admin)
    end

    test "one card per order", %{card: card, other_card: other_card, admin: admin} do
      order = placed_order(gift: true, recipient_name: "Anna")
      Pricing.link_card_to_gift_order!(card, order.id, actor: admin)

      assert {:error, _taken} = Pricing.link_card_to_gift_order(other_card, order.id, actor: admin)
    end

    test "a fulfilled gift keeps its card even when unlinked through Pricing", %{card: card, admin: admin} do
      gift = placed_order(gift: true)
      card = Pricing.link_card_to_gift_order!(card, gift.id, actor: admin, load: :gift_order_linkable?)
      ready = Orders.mark_order_ready!(gift, actor: admin)
      Orders.mark_order_fulfilled!(ready, %{email_customer?: false}, actor: admin)

      assert {:error, _fulfilled} = Pricing.link_card_to_gift_order(card, nil, actor: admin)
      assert Ash.reload!(card, authorize?: false).gift_order_id == gift.id
    end

    test "a card stays with its gift when its code is typed on another", %{card: card, admin: admin} do
      gift = placed_order(gift: true, recipient_name: "Anna")
      other_gift = placed_order(gift: true, recipient_name: "Bea")
      card = Pricing.link_card_to_gift_order!(card, gift.id, actor: admin)

      assert {:error, _taken} = Pricing.link_card_to_gift_order(card, other_gift.id, actor: admin)
      assert Ash.reload!(card, authorize?: false).gift_order_id == gift.id
    end

    test "only an admin links a card", %{card: card} do
      order = placed_order(gift: true, recipient_name: "Anna")
      assert {:error, %Ash.Error.Forbidden{}} = Pricing.link_card_to_gift_order(card, order.id, actor: nil)
    end
  end
end
