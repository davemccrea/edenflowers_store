defmodule EdenflowersWeb.Marketing.PassItOnLive do
  @moduledoc """
  Where a pass-it-on card's QR code leads: the recipient's discount and one of Jennie's Favourites to send on.
  `Plugs.ApplyLinkPromotion` has already put the code on the cart. A used or unknown code still shows the page,
  without the discount. A customer opening a card's page starts its code's 30 days.
  """

  use EdenflowersWeb, :live_view

  alias Edenflowers.Catalog
  alias Edenflowers.Format
  alias Edenflowers.Pricing
  alias Edenflowers.Translations

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_user_optional}

  @impl true
  def mount(params, _session, socket) do
    code = params["code"]
    promotion = code |> usable_promotion() |> start_validity(socket.assigns.current_user)

    product =
      Catalog.list_featured_products!()
      |> Enum.take(1)
      |> Translations.translate()
      |> List.first()

    {:ok,
     socket
     # The page shows the code itself.
     |> clear_flash(:success)
     |> assign(
       page_title: ~t"Pass it on",
       page_robots: "noindex",
       alternates: alternates("/#{language}/pass-it-on"),
       code: code,
       promotion: promotion,
       rate: promotion && Format.discount(promotion.discount_rate, Format.locale()),
       in_cart?: promotion != nil and socket.assigns.order != nil and socket.assigns.order.promotion_id == promotion.id,
       product: product
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      current_user={@current_user}
      order={@order}
      flash={@flash}
      current_path={@current_path}
      notice_bar={@notice_bar}
      alternates={@alternates}
    >
      <%!-- Phones read message, photo, then the favourite. From md the photo fills the right half to the window's
           edge and runs up under the fixed header, so the split fills the first screen. --%>
      <section class="md:min-h-[calc(100dvh-var(--notice-bar-height))] md:grid-rows-[auto_1fr] md:grid md:grid-cols-2">
        <div class="container pt-28 sm:pt-(--header-clearance) md:col-start-1 md:row-start-1 md:pr-16 lg:pr-24">
          <.flower
            name="flower-30"
            class="text-base-content/20 [--flower-spin-turn:4deg] -mb-3 -ml-3 h-12 w-12 md:-mb-4 md:h-16 md:w-16"
          />
          <h1 class="page-title relative mb-6">{~t"Pass it on"}</h1>
          <p class="text-base-content/80 max-w-prose text-lg leading-relaxed">
            {~t"Someone thought of you today. Now you can do the same for someone you care about 💛"}
          </p>

          <div :if={@promotion} id="pass-it-on-code" class="bg-cream text-cream-content mt-8 max-w-sm px-7 py-6">
            <p class="font-serif text-4xl leading-tight">{~t"#{@rate} off"}</p>
            <.code_line code={@promotion.code} in_cart?={@in_cart?} />
            <.valid_until date={@promotion.expiration_date} />
          </div>

          <p :if={@code && !@promotion} id="pass-it-on-code-unusable" class="text-base-content/65 mt-6">
            {~t"This code has already been used or is no longer valid."}
          </p>
        </div>

        <.link
          :if={@product}
          navigate={~q"/#{language}/product/#{@product}"}
          tabindex="-1"
          aria-hidden="true"
          class="bg-cream group mt-10 block overflow-hidden md:col-start-2 md:row-span-2 md:row-start-1 md:mt-0"
        >
          <.image
            src={@product.main_photo_slug}
            alt=""
            width={800}
            height={1000}
            sources={[%{media: "(min-width: 768px)", width: 1000, height: 1200}]}
            sizes="(min-width: 768px) 50vw, 100vw"
            priority
            class="aspect-[4/5] h-full w-full object-cover transition duration-700 ease-out group-hover:scale-[1.04] md:aspect-auto"
          />
        </.link>

        <div
          :if={@product}
          class="container pt-8 pb-20 md:col-start-1 md:row-start-2 md:self-end md:pr-16 md:pb-16 lg:pr-24"
        >
          <p class="text-base-content/65 text-xs uppercase tracking-wide">{~t"Popular"}</p>
          <h2 class="card-heading mt-1">
            {@product.name}
            <span class="text-base-content/65 font-sans text-sm">
              · {~t"from"} {Format.storefront_price(@product.cheapest_price, Format.locale())}
            </span>
          </h2>
          <div class="mt-5 flex flex-wrap items-center gap-6">
            <.button navigate={~q"/#{language}/product/#{@product}"} variant="primary">
              {~t"Send these flowers"}
            </.button>
            <.button navigate={~q"/#{language}/store"} variant="text">{~t"See all bouquets"}</.button>
          </div>
        </div>
      </section>
    </Layouts.app>
    """
  end

  attr :code, :any, required: true
  attr :in_cart?, :boolean, required: true

  defp code_line(%{in_cart?: true} = assigns) do
    gettext_comment("Split around the promo code, shown in bold: 'The code ABC123 is already in your cart.'")
    lead = ~t"The code"
    gettext_comment("Follows the promo code in bold: 'The code ABC123 is already in your cart.'")
    assigns = assign(assigns, lead: lead, tail: ~t"is already in your cart.")
    code_sentence(assigns)
  end

  defp code_line(assigns) do
    gettext_comment("Split around the promo code, shown in bold: 'Enter the code ABC123 at checkout.'")
    lead = ~t"Enter the code"
    gettext_comment("Follows the promo code in bold: 'Enter the code ABC123 at checkout.'")
    assigns = assign(assigns, lead: lead, tail: ~t"at checkout.")
    code_sentence(assigns)
  end

  attr :date, Date, default: nil

  defp valid_until(%{date: nil} = assigns), do: ~H""

  defp valid_until(assigns) do
    valid_until = Format.date(assigns.date, Format.locale())
    gettext_comment("Last day a pass-it-on card's code works, e.g. 'Valid until 5.12.2026.'")
    assigns = assign(assigns, text: ~t"Valid until #{valid_until}.")

    ~H"""
    <p class="text-cream-content/70 mt-3 text-sm">{@text}</p>
    """
  end

  defp code_sentence(assigns) do
    ~H"""
    <p class="text-cream-content/85 mt-2">
      {@lead} <strong class="text-cream-content font-semibold tracking-wider">{@code}</strong> {@tail}
    </p>
    """
  end

  defp usable_promotion(code) when is_binary(code) and code != "" do
    case Pricing.get_promotion_by_code(code) do
      {:ok, promotion} -> promotion
      {:error, _not_usable} -> nil
    end
  end

  defp usable_promotion(_code), do: nil

  defp start_validity(nil, _actor), do: nil
  defp start_validity(promotion, actor), do: Pricing.start_promotion_validity!(promotion, actor: actor)
end
