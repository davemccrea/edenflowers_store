# One-off helper: geocode real Vaasa delivery addresses through the app's HereAPI so the
# seeded today-delivery orders carry accurate coordinates and routing distances for the
# tour-planning spike. Run with `source .env && mix run scripts/geocode_seed_orders.exs`,
# then paste the printed maps into priv/repo/seeds.exs. Not part of the app runtime.

orders = [
  %{
    customer_name: "Petteri Salo",
    customer_email: "petteri.salo@example.fi",
    recipient_name: "Petteri Salo",
    recipient_phone_number: "+358 40 511 2233",
    address: "Hovioikeudenpuistikko 15, 65100 Vaasa",
    gift: false,
    locale: "fi",
    items: [{"Bouquet 2", :medium, 1}]
  },
  %{
    customer_name: "Anna Heikkilä",
    customer_email: "anna.heikkila@example.fi",
    recipient_name: "Markus Heikkilä",
    recipient_phone_number: "+358 50 233 4455",
    address: "Vöyrinkatu 16, 65100 Vaasa",
    gift: true,
    card_message: "Grattis på födelsedagen!",
    card: {"Card 1", :medium},
    items: [{"Bouquet 5", :large, 1}]
  },
  %{
    customer_name: "Johanna Mäki",
    customer_email: "johanna.maki@example.fi",
    recipient_name: "Johanna Mäki",
    recipient_phone_number: "+358 44 677 8899",
    address: "Palosaarentie 24, 65200 Vaasa",
    gift: false,
    items: [{"Plant 2", :medium, 1}, {"Bouquet 1", :small, 1}]
  },
  %{
    customer_name: "Ville Korhonen",
    customer_email: "ville.korhonen@example.fi",
    recipient_name: "Ville Korhonen",
    recipient_phone_number: "+358 41 100 2030",
    address: "Ristinummentie 10, 65300 Vaasa",
    gift: false,
    locale: "fi",
    items: [{"Bouquet 4", :medium, 2}]
  },
  %{
    customer_name: "Sofia Nieminen",
    customer_email: "sofia.nieminen@example.fi",
    recipient_name: "Eeva Nieminen",
    recipient_phone_number: "+358 40 909 1122",
    address: "Huutoniementie 14, 65320 Vaasa",
    gift: true,
    card_message: "Tänker på dig.",
    card: {"Card 3", :medium},
    items: [{"Bouquet 6", :medium, 1}]
  },
  %{
    customer_name: "Lauri Virtanen",
    customer_email: "lauri.virtanen@example.fi",
    recipient_name: "Lauri Virtanen",
    recipient_phone_number: "+358 50 445 6677",
    address: "Isolahdentie 18, 65380 Vaasa",
    gift: false,
    items: [{"Plant 3", :large, 1}]
  },
  %{
    customer_name: "Emilia Laine",
    customer_email: "emilia.laine@example.fi",
    recipient_name: "Emilia Laine",
    recipient_phone_number: "+358 44 332 1100",
    address: "Kirkkopuistikko 24, 65100 Vaasa",
    gift: false,
    locale: "fi",
    items: [{"Bouquet 3", :small, 1}, {"Plant 1", :small, 1}]
  },
  %{
    customer_name: "Oskari Järvi",
    customer_email: "oskari.jarvi@example.fi",
    recipient_name: "Oskari Järvi",
    recipient_phone_number: "+358 40 778 9900",
    address: "Vamiankatu 6, 65350 Vaasa",
    gift: false,
    items: [{"Bouquet 1", :large, 1}]
  }
]

format_items = fn items ->
  items
  |> Enum.map(fn {name, size, qty} -> "{#{inspect(name)}, #{inspect(size)}, #{qty}}" end)
  |> Enum.join(", ")
end

for order <- orders do
  case Edenflowers.HereAPI.get_address(order.address) do
    {:ok, {geocoded_address, position, here_id}} ->
      distance =
        case Edenflowers.HereAPI.get_distance(position) do
          {:ok, d} -> d
          _ -> 0
        end

      IO.puts("""
        %{
          customer_name: #{inspect(order.customer_name)},
          customer_email: #{inspect(order.customer_email)},
          fulfillment_option: home_delivery,
          fulfillment_date: today,
          recipient_name: #{inspect(order.recipient_name)},
          recipient_phone_number: #{inspect(order.recipient_phone_number)},
          delivery_address: #{inspect(order.address)},
          geocoded_address: #{inspect(geocoded_address)},
          position: #{inspect(position)},
          here_id: #{inspect(here_id)},
          distance: #{distance},
          gift: #{order.gift},#{if order[:locale], do: "\n      locale: #{inspect(order.locale)},", else: ""}#{if order[:card_message], do: "\n      card_message: #{inspect(order.card_message)},", else: ""}#{if order[:card], do: "\n      card: {#{inspect(elem(order.card, 0))}, #{inspect(elem(order.card, 1))}},", else: ""}
          items: [#{format_items.(order.items)}]
        },\
      """)

    error ->
      IO.puts("  # FAILED to geocode #{order.address}: #{inspect(error)}")
  end
end
