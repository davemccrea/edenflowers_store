defmodule EdenflowersWeb.Store.StoreLive do
  @moduledoc """
  Public catalogue page for browsing products by category.
  """

  use EdenflowersWeb, :live_view

  alias Edenflowers.Catalog
  alias Edenflowers.Format
  alias Edenflowers.Fulfillment
  alias Edenflowers.Translations

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_user_optional}

  # Fewer cards than this make a sparse fan, so the section waits until Jennie ticks enough.
  @min_fan_cards 5

  @impl true
  def mount(_params, _session, socket) do
    categories = Catalog.list_categories!()
    # Found before translating, as translation replaces the English slug.
    bouquets_id = Enum.find_value(categories, &(&1.slug == "bouquets" && &1.id))
    categories = Translations.translate(categories)
    bouquets = Enum.find(categories, &(&1.id == bouquets_id))

    {:ok,
     assign(socket,
       alternates: alternates("/#{language}/store"),
       categories: categories,
       bouquets: bouquets,
       products: [],
       free_dist_km: Fulfillment.free_dist_km(),
       selected_category: nil,
       cards: Catalog.list_featured_cards!() |> Translations.translate(),
       card_price_from: card_price_from(Catalog.list_card_drawer_variants!(), Format.locale()),
       delivery_fee: delivery_fee(Format.locale())
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    case Map.get(params, "category") do
      nil ->
        show_bouquets(socket)

      category_slug ->
        case load_products(category_slug) do
          {:ok, products, selected_category, alternates} ->
            {:noreply,
             assign(socket,
               alternates: alternates,
               page_title: ~t"#{category = selected_category.name} in Vaasa",
               page_description: selected_category.description,
               products: products,
               selected_category: selected_category
             )}

          :error ->
            raise Ash.Error.Query.NotFound, resource: Catalog.ProductCategory
        end
    end
  end

  def min_fan_cards, do: @min_fan_cards

  defp show_card_fan?(cards), do: length(cards) >= @min_fan_cards

  defp card_price_from([], _locale), do: nil

  defp card_price_from(variants, locale) do
    variants |> Enum.map(& &1.price) |> Enum.min(Decimal) |> Format.storefront_price(locale)
  end

  defp delivery_fee(locale) do
    case Fulfillment.distance_priced_delivery() do
      nil ->
        nil

      %{free_dist_km: km, base_price: base, price_per_km: per_km} when is_integer(km) and km > 0 ->
        ~t"#{base = Format.storefront_price(base, locale)} plus #{per_km = Format.storefront_price(per_km, locale)} per km. On chosen bouquets the first #{km = km} km are free."

      %{base_price: base, price_per_km: per_km} ->
        ~t"#{base = Format.storefront_price(base, locale)} plus #{per_km = Format.storefront_price(per_km, locale)} per km."
    end
  end

  defp show_bouquets(%{assigns: %{bouquets: nil}} = socket),
    do: {:noreply, assign(socket, page_title: ~t"Store", products: [], selected_category: nil)}

  defp show_bouquets(socket),
    do: {:noreply, push_patch(socket, to: ~q"/#{language}/store/#{socket.assigns.bouquets.slug}", replace: true)}

  @impl true
  def render(assigns) do
    assigns =
      assign(
        assigns,
        :other_categories?,
        Enum.any?(assigns.categories, fn category ->
          is_nil(assigns.selected_category) or category.id != assigns.selected_category.id
        end)
      )

    ~H"""
    <Layouts.app
      current_user={@current_user}
      order={@order}
      flash={@flash}
      current_path={@current_path}
      notice_bar={@notice_bar}
      alternates={@alternates}
    >
      <.container>
        <h1 class="page-title mb-4">
          {if @selected_category, do: @selected_category.name, else: ~t"Store"}
        </h1>
        <p
          :if={@selected_category && @selected_category.description}
          class="font-serif text-base-content/85 max-w-[48ch] text-lg italic"
        >
          {@selected_category.description}
        </p>

        <nav :if={@categories != []} aria-label={~t"Categories"} class="mt-8 mb-12 md:mb-16">
          <ol class="category-index [scrollbar-width:none] m-0 flex list-none gap-x-8 overflow-x-auto whitespace-nowrap p-0">
            <li :for={category <- @categories}>
              <.link
                patch={~q"/#{language}/store/#{category.slug}"}
                class="category-index__link text-base-content touch-target block py-2 no-underline"
                aria-current={@selected_category && @selected_category.id == category.id && "page"}
              >
                <span class="category-index__name font-serif text-lg md:text-xl">{category.name}</span>
              </.link>
            </li>
          </ol>
        </nav>

        <div id="store-products">
          <%= if Enum.empty?(@products) do %>
            <div class="bg-cream flex flex-col items-center gap-5 px-8 py-20 text-center sm:py-24">
              <.flower name="flower-42" class="text-primary/80 h-20 w-20" />
              <h2 class="section-title text-primary">{~t"Nothing listed here just now"}</h2>
              <p class="text-base-content/75 max-w-md leading-relaxed">
                <%= if @other_categories? do %>
                  {~t"Browse another collection, or get in touch to ask about flowers for your occasion."}
                <% else %>
                  {~t"Need flowers before then? Get in touch and I'll gladly help."}
                <% end %>
              </p>
              <div class="mt-2 flex flex-wrap justify-center gap-3">
                <.button
                  :if={@selected_category && @bouquets && @selected_category.id != @bouquets.id}
                  patch={~q"/#{language}/store/#{@bouquets.slug}"}
                  variant="primary"
                >
                  {~t"Browse bouquets"}
                </.button>
                <.button navigate={~q"/#{language}/contact"} variant="secondary">
                  {~t"Get in touch"}
                </.button>
              </div>
            </div>
          <% else %>
            <.free_delivery_note
              :if={@free_dist_km && Enum.any?(@products, & &1.free_delivery)}
              free_dist_km={@free_dist_km}
              class="mb-8"
            />
            <ul
              class="grid gap-x-6 gap-y-16 md:grid-cols-2 md:gap-y-20 xl:grid-cols-3 xl:gap-x-8"
              role="list"
            >
              <li :for={{product, index} <- Enum.with_index(@products)}>
                <.product_card
                  product={product}
                  priority={index == 0}
                  navigate={~q"/#{language}/product/#{product}"}
                  locale={Edenflowers.Format.locale()}
                  heading="h2"
                  free_dist_km={@free_dist_km}
                />
              </li>
            </ul>
          <% end %>
        </div>
      </.container>

      <section
        :if={show_card_fan?(@cards)}
        id="cards"
        class="overflow-x-clip border-t"
        aria-labelledby="cards-heading"
      >
        <div class="container grid items-center gap-12 py-20 md:py-28 lg:grid-cols-2">
          <div class="lg:order-last">
            <ul
              id="card-fan"
              phx-hook=".CardFan"
              class="card-fan"
              style={"--n: #{length(@cards)};"}
              aria-label={~t"Cards"}
            >
              <li :for={{card, i} <- Enum.with_index(@cards)} style={"--i: #{i};"}>
                <button type="button">
                  <%!-- Card artwork is fine line work, which looks soft at the default WebP quality. --%>
                  <.image
                    src={card.main_photo_slug}
                    alt={card.name}
                    width={487}
                    height={611}
                    crop_type="fit"
                    quality={90}
                    sizes="(min-width: 768px) 13rem, 9.5rem"
                  />
                </button>
              </li>
            </ul>
            <%!-- Names the card that is picked up, or pointed at or focused. --%>
            <p
              id="card-fan-caption"
              phx-update="ignore"
              class="card-fan-caption text-base-content/80 font-serif text-xl italic"
              aria-live="polite"
            >
            </p>
          </div>
          <script :type={Phoenix.LiveView.ColocatedHook} name=".CardFan">
            export default {
              mounted() {
                this.observer = new IntersectionObserver(
                  ([entry]) => {
                    if (entry.isIntersecting) {
                      this.js().setAttribute(this.el, "data-open", "");
                      this.observer.disconnect();
                    }
                  },
                  { threshold: 0.6 },
                );
                this.observer.observe(this.el);

                this.caption = document.getElementById("card-fan-caption");

                // Clicking a card brings it to the front, swapping out any card already there.
                // Clicking it again, Escape or a click on the page puts it back. Clicks on other
                // links and buttons leave it out, since they have their own job to do.
                this.click = (event) => {
                  const card = this.el.contains(event.target) && event.target.closest("li");
                  if (card)
                    return card === this.selected()
                      ? this.putBack()
                      : this.bringToFront(card);
                  if (this.selected() && !event.target.closest("a, button")) this.putBack();
                };
                this.escape = (event) => {
                  if (event.key === "Escape" && this.selected()) this.putBack();
                };
                document.addEventListener("click", this.click);
                document.addEventListener("keydown", this.escape);

                // Pointing at or focusing a card names it while no card is picked up. Touch has
                // no hover, so a tap names the card by picking it up.
                const point = (card) => {
                  this.pointed = card;
                  this.name();
                };
                this.el.addEventListener("pointerover", (event) => {
                  if (event.pointerType === "mouse") point(event.target.closest("li"));
                });
                this.el.addEventListener("pointerleave", () => point(null));
                this.el.addEventListener("focusin", (event) =>
                  point(event.target.closest("li")),
                );
                this.el.addEventListener("focusout", () => point(null));
              },

              selected() {
                return this.el.querySelector("li[data-selected]");
              },

              // Names the card picked up, or else the one pointed at or focused. A picked-up card
              // moves out from under the pointer, so pointing must not take the name from it.
              name() {
                const named = this.selected() || this.pointed;
                if (named) {
                  this.caption.textContent = named.querySelector("img").alt;
                  this.js().setAttribute(this.caption, "data-shown", "");
                } else {
                  this.js().removeAttribute(this.caption, "data-shown");
                }
              },

              // A card swapped out drops straight back without its own hop, so the only card
              // that moves is the one coming to the front.
              bringToFront(card) {
                if (this.selected())
                  this.js().removeAttribute(this.selected(), "data-selected");
                this.js().removeAttribute(card, "data-put-back");
                this.js().setAttribute(card, "data-selected", "");
                this.name();
              },

              putBack() {
                const card = this.selected();
                this.js().removeAttribute(card, "data-selected");
                this.js().setAttribute(card, "data-put-back", "");
                this.name();
              },

              destroyed() {
                this.observer.disconnect();
                document.removeEventListener("click", this.click);
                document.removeEventListener("keydown", this.escape);
              },
            };
          </script>

          <div class="flex flex-col items-start">
            <h2 id="cards-heading" class="section-title mb-6">{~t"Your words, written by hand"}</h2>
            <p :if={@card_price_from} class="eyebrow text-base-content/70 mb-4">
              {~t"Cards from #{price = @card_price_from}"}
            </p>
            <p class="text-base-content/80 max-w-prose text-lg leading-relaxed">
              {~t"Choose a card at checkout and add your message. Jennie writes it out and tucks it in with the flowers."}
            </p>
          </div>
        </div>
      </section>

      <section class="border-t" aria-labelledby="location-heading">
        <div class="grid md:grid-cols-2">
          <div class="flex flex-col px-4 pt-8 pb-16 sm:px-8 md:justify-center md:px-12 md:py-32 lg:px-20">
            <.flower
              name="flower-41"
              class="text-base-content/20 [--flower-spin-turn:4deg] -mb-4 -ml-4 h-16 w-16 md:-mb-5 md:h-20 md:w-20"
            />
            <h2 id="location-heading" class="section-title relative mb-8">{~t"Delivery and pickup"}</h2>
            <dl class="grid max-w-prose gap-6 text-lg leading-relaxed">
              <div :if={@delivery_fee}>
                <dt class="eyebrow text-base-content/70 mb-1">{~t"Delivery"}</dt>
                <dd>{@delivery_fee}</dd>
              </div>
              <div>
                <dt class="eyebrow text-base-content/70 mb-1">{~t"Pickup"}</dt>
                <dd>{~t"Always free from Minimossen."}</dd>
              </div>
            </dl>
          </div>

          <%!-- On desktop the map fills the text column's height instead of setting its own --%>
          <div class="order-first md:relative md:order-none">
            <.image
              src="local:///home-vaasa-map-10.png"
              alt={~t"Map of Vaasa, Finland with Minimossen pinned"}
              width={1600}
              height={1880}
              sizes="(min-width: 768px) 50vw, 100vw"
              quality={95}
              class="aspect-[4/3] [mask-image:linear-gradient(to_bottom,black_90%,transparent)] max-h-80 w-full object-cover md:aspect-auto md:max-h-none md:[mask-image:linear-gradient(to_right,transparent,black_10%)] md:absolute md:inset-0 md:h-full"
            />
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end

  defp load_products(category_slug) do
    case Catalog.get_category_by_slug(category_slug) do
      {:ok, category} ->
        products = category.id |> Catalog.list_products_by_category!() |> Translations.translate()
        {:ok, products, Translations.translate(category), alternates("/#{language}/store/#{category.slug}")}

      {:error, _} ->
        :error
    end
  end
end
