defmodule EdenflowersWeb.CardDrawer do
  @moduledoc """
  The drawer of cards to choose from, at checkout and on Jennie's order form.
  Choosing one sends `select_card` with its `variant-id` to the LiveView.
  """
  use EdenflowersWeb, :html

  import EdenflowersWeb.Admin.Drawers, only: [admin_drawer: 1, drawer_body: 1]

  alias Edenflowers.Catalog.ProductType
  alias Edenflowers.Catalog.ProductVariantSize

  attr :variants, :list, required: true
  attr :locale, :string, required: true
  attr :selected_variant_id, :string, default: nil
  attr :admin?, :boolean, default: false, doc: "whether it opens in the admin, with the admin drawer's width and header"

  def card_drawer(assigns) do
    # Sizes are stored as text, so the database would sort Large before Small.
    size_groups =
      for size <- ProductVariantSize.values() ++ [nil],
          variants = Enum.filter(assigns.variants, &(&1.size == size)),
          variants != [] do
        variants = Enum.sort_by(variants, &{is_nil(&1.product.position), &1.product.position, &1.product.name})
        {size, shared_price(variants), shared_details(variants), variants}
      end

    assigns = assign(assigns, :size_groups, size_groups)

    ~H"""
    <.drawer
      :if={!@admin?}
      id="card-drawer"
      placement="right"
      label={gettext("Select a card")}
      class="bg-base-100 w-[80vw] flex h-full flex-col overflow-y-auto overscroll-contain sm:w-[25rem] lg:w-[34rem]"
    >
      <header class="flex flex-row items-center justify-between gap-4 pt-6 pr-4 pl-4 sm:pt-8 sm:pl-8">
        <h2 class="section-title">{gettext("Select a card")}</h2>
        <.icon_button aria_label={~t"Close"} phx-click={JS.exec("phx-hide", to: "#card-drawer")}>
          <.icon name="hero-x-mark" class="h-6 w-6 hover:text-base-content/60" />
        </.icon_button>
      </header>

      <div class="flex flex-col gap-6 p-4 sm:p-8" data-testid="card-drawer">
        <.card_content size_groups={@size_groups} locale={@locale} selected_variant_id={@selected_variant_id} />
      </div>
    </.drawer>

    <.admin_drawer :if={@admin?} id="card-drawer" title={~t"Select a card"}>
      <.drawer_body>
        <div class="flex flex-col gap-6" data-testid="card-drawer">
          <.card_content size_groups={@size_groups} locale={@locale} selected_variant_id={@selected_variant_id} />
        </div>
      </.drawer_body>
    </.admin_drawer>
    """
  end

  attr :size_groups, :list, required: true
  attr :locale, :string, required: true
  attr :selected_variant_id, :string, default: nil

  defp card_content(assigns) do
    ~H"""
    <div :for={{size, shared_price, shared_details, variants} <- @size_groups} class="flex flex-col gap-3">
      <div class="flex items-end justify-between gap-3">
        <div class="flex flex-col gap-1">
          <h3 class="eyebrow text-base-content/70">{variant_size_label(size)}</h3>
          <span :if={message_room_label(size)} class="text-base-content/70 text-sm">
            {message_room_label(size)}
          </span>
          <span :if={shared_details} class="text-base-content/70 text-sm">{shared_details}</span>
        </div>
        <span :if={shared_price} class="font-serif text-lg">{Edenflowers.Format.currency(shared_price, @locale)}</span>
      </div>
      <div class="grid grid-cols-2 gap-3 lg:grid-cols-3">
        <button
          :for={variant <- variants}
          type="button"
          phx-click={
            JS.push("select_card", value: %{"variant-id" => variant.id})
            |> JS.exec("phx-hide", to: "#card-drawer")
          }
          aria-current={variant.id == @selected_variant_id && "true"}
          class={["press relative flex flex-col items-center gap-1 border p-2 hover:border-primary", if(variant.id == @selected_variant_id,
    do: "border-primary bg-primary/5",
    else: "border-base-300")]}
          data-testid={"card-option-#{variant.id}"}
        >
          <span
            :if={variant.id == @selected_variant_id}
            class="bg-primary text-primary-content absolute top-3 right-3 flex h-5 w-5 items-center justify-center rounded-full"
          >
            <.icon name="hero-check-mini" class="h-3.5 w-3.5" />
          </span>
          <%!-- Card artwork is fine line work, which looks soft at the default WebP quality. --%>
          <.image
            src={variant.photo_slug}
            alt=""
            width={160}
            height={160}
            sizes="8rem"
            crop_type="fit"
            quality={90}
            loading="eager"
            class="aspect-square w-full object-contain p-2"
          />
          <%!-- Card names run to 16 characters, wider than a two-column tile on a phone. --%>
          <span class="font-serif text-balance hyphens-auto wrap-break-word w-full text-center text-lg leading-snug">
            {variant.product.name}
          </span>
          <span :if={is_nil(shared_details) && details(variant)} class="text-base-content/70 text-sm">
            {details(variant)}
          </span>
          <span :if={is_nil(shared_price)} class="font-serif text-lg">
            {Edenflowers.Format.currency(variant.price, @locale)}
          </span>
        </button>
      </div>
    </div>
    """
  end

  # The heading shows the price only when every card of the size costs it,
  # so one dearer card can't make the whole size look cheaper.
  defp shared_price([first | rest]) do
    if Enum.all?(rest, &Decimal.equal?(&1.price, first.price)), do: first.price
  end

  # Like the price: in the heading only when every card of the size shares it.
  defp shared_details(variants) do
    case variants |> Enum.map(&details/1) |> Enum.uniq() do
      [details] -> details
      _ -> nil
    end
  end

  defp details(variant), do: ProductType.describe(:card, variant)

  # Words, not a character count: the counter under the message shows the
  # exact limit, and a word count would differ from language to language.
  defp message_room_label(:small), do: ~t"Room for a short note"
  defp message_room_label(:medium), do: ~t"Room for a few lines"
  defp message_room_label(:large), do: ~t"Room for a longer message"
  defp message_room_label(nil), do: nil
end
