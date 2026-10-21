defmodule EdenflowersWeb.Admin.ProductFormLive do
  use EdenflowersWeb, :live_view

  import EdenflowersWeb.Admin.Components
  import EdenflowersWeb.Admin.TranslationFields

  alias Edenflowers.Catalog.Product
  alias Edenflowers.Catalog.ProductCategory
  alias Edenflowers.Catalog.ProductVariantSize
  alias Edenflowers.Pricing
  alias EdenflowersWeb.Admin.PhotoUpload
  alias EdenflowersWeb.Admin.TranslationFields
  alias EdenflowersWeb.Layouts

  on_mount {EdenflowersWeb.Auth.LiveUserAuth, :live_admin_required}

  @max_photos 8

  @impl true
  def mount(params, _session, socket) do
    actor = socket.assigns.current_user

    case load_form(params, actor) do
      {:ok, title, form} ->
        {:ok,
         socket
         |> assign(:page_title, title)
         |> assign(:categories, Ash.read!(ProductCategory, actor: actor))
         |> assign(:tax_rates, Pricing.list_selectable_tax_rates!(actor: actor))
         |> assign(:free_dist_km, Edenflowers.Fulfillment.free_dist_km())
         |> assign(:form, form)
         |> assign(:translating, nil)
         |> assign(:max_photos, @max_photos)
         |> PhotoUpload.allow_many(:photos,
           max_entries: @max_photos,
           auto_upload: true,
           progress: &handle_photo_progress/3
         )}

      :error ->
        {:ok,
         socket
         |> put_flash(:error, ~t"Product not found.")
         |> push_navigate(to: ~p"/admin/products")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.admin flash={@flash} current_path={@current_path} current_user={@current_user}>
      <.admin_page>
        <.form
          for={@form}
          id="product-form"
          data-warn-unsaved={~t"You have unsaved changes. Leave without saving?"}
          phx-change="validate"
          phx-submit="save"
        >
          <%!-- Below the phone topbar, which is sticky too; from lg it's gone. The actions share
               the back link's row so the header stays short on a phone. --%>
          <div class="bg-base-100 border-base-content/12 top-[calc(env(safe-area-inset-top)+4rem)] [&>header]:mb-3 [&>header>div:first-child]:mb-1 sticky z-20 -mx-4 mb-6 border-b px-4 pt-3 sm:-mx-6 sm:px-6 lg:top-0 lg:-mx-8 lg:-mt-8 lg:px-8 lg:pt-6">
            <.admin_page_header title={@page_title} back={{~t"Products", ~p"/admin/products"}}>
              <:subtitle :if={@form.source.type == :update && @form.source.data.sold_out?}>
                <.badge tone={:warning}>{~t"Sold out"}</.badge>
              </:subtitle>
              <:nav>
                <div class="[&_.fieldset]:mb-0 flex items-center gap-2">
                  <.input field={@form[:draft]} type="checkbox" label={~t"Draft"} class="toggle toggle-primary" />
                  <.button
                    :if={@form.source.type == :update && !@form.source.data.draft}
                    href={~q"/#{language}/product/#{@form.source.data.id}"}
                    target="_blank"
                    variant="secondary"
                    size="sm"
                  >
                    <.icon name="hero-arrow-top-right-on-square" class="h-4 w-4" />
                    <span class="max-sm:sr-only">{~t"View in store"}</span>
                  </.button>
                  <.button type="submit" variant="primary" size="sm" phx-disable-with={~t"Saving…"}>
                    {~t"Save"}
                  </.button>
                </div>
              </:nav>
            </.admin_page_header>
          </div>

          <div class="grid grid-cols-1 gap-6 xl:grid-cols-[minmax(0,1fr)_22rem] xl:items-start">
            <div class="space-y-6">
              <.form_section title={~t"Photos"}>
                <:description>
                  {~t"Up to #{count = @max_photos}. The main photo shows in the store's listings."}
                </:description>
                <.photo_gallery
                  field={@form[:photo_slugs]}
                  photo_slugs={photo_slugs(@form)}
                  upload={@uploads.photos}
                  max={@max_photos}
                  show_errors={@form.source.submitted_once?}
                />
              </.form_section>

              <.form_section title={~t"Sizes and prices"}>
                <ul class="border-base-content/12 divide-base-content/8 divide-y border">
                  <.inputs_for :let={variant} field={@form[:product_variants]}>
                    <.size_row
                      variant={variant}
                      photo_slugs={photo_slugs(@form)}
                      show_errors={@form.source.submitted_once?}
                    />
                  </.inputs_for>
                </ul>
                <div class="mt-3 flex flex-wrap items-center justify-between gap-3">
                  <.button type="button" phx-click="add_variant" variant="secondary" size="sm">
                    <.icon name="hero-plus" class="h-4 w-4" /> {~t"Add size"}
                  </.button>
                  <.button
                    type="button"
                    phx-click="mark_sold_out"
                    variant="secondary"
                    size="sm"
                    data-testid="mark-sold-out"
                  >
                    {~t"Mark every size sold out"}
                  </.button>
                </div>
              </.form_section>

              <.form_section title={~t"Name and description"}>
                <.language_fields form={@form} translating={@translating} />
              </.form_section>
            </div>

            <aside class="xl:sticky xl:top-36">
              <.form_section title={~t"In the store"}>
                <div class="space-y-4">
                  <.input
                    field={@form[:product_category_id]}
                    type="select"
                    label={~t"Category"}
                    prompt={~t"Choose a category"}
                    options={Enum.map(@categories, &{&1.name, &1.id})}
                    class="select w-full"
                  />
                  <.input
                    field={@form[:tax_rate_id]}
                    type="select"
                    label={~t"VAT"}
                    options={Enum.map(@tax_rates, &{&1.name, &1.id})}
                    class="select w-full"
                  />
                  <.input
                    field={@form[:position]}
                    type="number"
                    min="0"
                    label={~t"Position in store (0 = first)"}
                    class="input max-w-48 w-full tabular-nums"
                  />
                  <div class="[&_.fieldset]:mb-0">
                    <.input field={@form[:featured]} type="checkbox" label={~t"Featured on the home page"} />
                    <.input
                      :if={@free_dist_km}
                      field={@form[:free_delivery]}
                      type="checkbox"
                      label={~t"Free delivery within #{km = @free_dist_km} km"}
                    />
                    <.input
                      field={@form[:subscribable]}
                      type="checkbox"
                      label={~t"Can be bought as a subscription"}
                    />
                  </div>
                </div>
              </.form_section>
            </aside>
          </div>
        </.form>
      </.admin_page>
    </Layouts.admin>
    """
  end

  attr :field, Phoenix.HTML.FormField, required: true
  attr :photo_slugs, :list, required: true
  attr :upload, Phoenix.LiveView.UploadConfig, required: true
  attr :max, :integer, required: true
  attr :show_errors, :boolean, required: true

  defp photo_gallery(assigns) do
    upload = assigns.upload

    assigns =
      assign(assigns,
        upload_errors: Enum.uniq(upload_errors(upload) ++ Enum.flat_map(upload.entries, &upload_errors(upload, &1))),
        errors: if(assigns.show_errors, do: assigns.field.errors, else: [])
      )

    ~H"""
    <div phx-drop-target={@upload.ref}>
      <ul id="product-photos" class="grid grid-cols-3 gap-3 sm:grid-cols-5">
        <li :for={{slug, index} <- Enum.with_index(@photo_slugs)} data-testid="product-photo">
          <input type="hidden" name={@field.name <> "[]"} value={slug} />
          <span class="bg-cream aspect-[4/5] relative block overflow-hidden">
            <.image src={slug} alt="" width={240} height={300} class="absolute inset-0 h-full w-full object-cover" />
            <.badge
              :if={index == 0}
              tone={:neutral}
              icon="hero-star-solid"
              class="[&_.hero-star-solid]:text-primary absolute top-1.5 left-1.5"
            >
              {~t"Main"}
            </.badge>
            <.button
              :if={index > 0}
              type="button"
              size="sm"
              phx-click="make_main_photo"
              phx-value-slug={slug}
              aria-label={~t"Make photo #{n = index + 1} main"}
              class="btn-square absolute top-1.5 left-1.5"
            >
              <.icon name="hero-star" class="text-primary size-4" />
            </.button>
            <%!-- A product always has a photo, so the last one is replaced rather than removed. --%>
            <.button
              :if={length(@photo_slugs) > 1}
              type="button"
              size="sm"
              phx-click="remove_photo"
              phx-value-slug={slug}
              aria-label={~t"Remove photo #{n = index + 1}"}
              class="btn-square absolute top-1.5 right-1.5"
            >
              <.icon name="hero-x-mark" class="size-4" />
            </.button>
          </span>
        </li>
        <li :for={entry <- @upload.entries} class="bg-cream aspect-[4/5] relative overflow-hidden">
          <.live_img_preview entry={entry} class="absolute inset-0 h-full w-full object-cover opacity-50" />
          <div class="absolute inset-0 grid place-items-center">
            <div
              class="radial-progress bg-base-100/80 [--size:3.5rem] text-sm"
              style={"--value:#{entry.progress}"}
              role="progressbar"
              aria-valuenow={entry.progress}
            >
              {entry.progress}%
            </div>
          </div>
        </li>
        <li :if={length(@photo_slugs) + length(@upload.entries) < @max}>
          <label class="group outline-primary block has-[:focus-visible]:outline-2 has-[:focus-visible]:outline-offset-2">
            <span class="border-base-content/25 text-cream-content/70 bg-cream aspect-[4/5] flex flex-col items-center justify-center gap-1 border border-dashed px-2 text-center transition-colors group-hover:border-base-content/50">
              <.icon name="hero-camera" class="size-7" />
              <span class="text-sm font-medium">{~t"Add photos"}</span>
              <span class="text-xs">{~t"or drop them here"}</span>
            </span>
            <.live_file_input upload={@upload} class="sr-only" />
          </label>
        </li>
      </ul>
    </div>
    <p :for={err <- @upload_errors} class="text-error mt-1.5 text-sm">{photo_upload_error(err)}</p>
    <.error :for={msg <- Enum.map(@errors, &translate_error/1)}>{msg}</.error>
    """
  end

  attr :variant, Phoenix.HTML.Form, required: true
  attr :photo_slugs, :list, required: true
  attr :show_errors, :boolean, required: true

  # One line per size from sm. On a phone the photo spans two lines: size and
  # remove, then price, stock and draft.
  defp size_row(assigns) do
    variant = assigns.variant
    [main | others] = assigns.photo_slugs ++ [nil]
    own = Enum.find(others, &(&1 && &1 == variant[:own_photo_slug].value))

    assigns =
      assign(assigns,
        main: main,
        own: own,
        size_label: size_label(variant[:size].value),
        drawer: "size-photo-#{variant.index}",
        picks?: length(assigns.photo_slugs) > 1,
        errors: if(assigns.show_errors, do: variant[:own_photo_slug].errors, else: [])
      )

    ~H"""
    <%!-- On a phone the select shows the size, so its label is for screen readers, and Draft's
         label sits above its toggle like a column's. From sm the first row's labels head the
         columns; later rows keep theirs for screen readers. --%>
    <li class="p-3 max-sm:[&_label:has(select)>span]:sr-only sm:[&:not(:first-of-type)_label.flex-col>span]:sr-only">
      <div class="grid-cols-[3rem_minmax(0,1fr)_auto] grid items-end gap-x-3 max-sm:[&_.fieldset-label]:flex-col-reverse max-sm:[&_.fieldset-label]:items-start max-sm:[&_.fieldset-label]:gap-3 sm:grid-cols-[2.5rem_minmax(0,1fr)_7rem_7rem_auto_auto]">
        <button
          :if={@picks?}
          type="button"
          phx-click={JS.exec("phx-show", to: "##{@drawer}")}
          aria-label={~t"Photo for #{size = @size_label}"}
          aria-controls={@drawer}
          class="bg-cream aspect-[4/5] outline-primary relative row-span-2 block w-12 self-start overflow-hidden outline-offset-2 hover:outline-1 focus-visible:outline-2 sm:row-span-1 sm:w-10 sm:self-auto"
        >
          <.size_thumbnail slug={@own || @main} main?={is_nil(@own)} />
        </button>
        <span
          :if={!@picks?}
          class="bg-cream aspect-[4/5] relative row-span-2 block w-12 self-start overflow-hidden sm:row-span-1 sm:w-10 sm:self-auto"
        >
          <.size_thumbnail :if={@main} slug={@main} main?={false} />
        </span>
        <.input
          field={@variant[:size]}
          type="select"
          label={~t"Size"}
          prompt={~t"One size"}
          options={Enum.map(ProductVariantSize.values(), &{variant_size_label(&1), &1})}
          class="select w-full"
        />
        <div class="grid-cols-[5rem_minmax(0,1fr)_auto] col-span-2 col-start-2 row-start-2 mt-3 grid items-end gap-3 sm:contents">
          <.input
            field={@variant[:price]}
            type="text"
            inputmode="decimal"
            label={~t"Price (€)"}
            class="input w-full tabular-nums"
          />
          <%!-- ponytail: saving sends the count shown when the form opened, so a sale made
               meanwhile is undone and may oversell later. Send only changed counts if that bites. --%>
          <.input
            field={@variant[:stock_quantity]}
            type="number"
            min="0"
            label={~t"In stock"}
            placeholder={~t"Unlimited"}
            class="input w-full tabular-nums"
          />
          <.input field={@variant[:draft]} type="checkbox" label={~t"Draft"} class="toggle toggle-primary" />
        </div>
        <.icon_button
          phx-click="remove_variant"
          phx-value-path={@variant.name}
          aria_label={~t"Remove #{size = @size_label}"}
        >
          <.icon name="hero-trash" class="size-5" />
        </.icon_button>
      </div>
      <.error :for={msg <- Enum.map(@errors, &translate_error/1)}>{msg}</.error>

      <.admin_drawer :if={@picks?} id={@drawer} title={~t"Photo for #{size = @size_label}"}>
        <.drawer_body>
          <fieldset>
            <legend class="sr-only">{~t"Photo for #{size = @size_label}"}</legend>
            <div class="grid grid-cols-2 gap-3">
              <%!-- The main photo submits "", so the size follows whichever photo is main. --%>
              <label
                :for={{slug, index} <- Enum.with_index(@photo_slugs)}
                phx-click={JS.exec("phx-hide", to: "##{@drawer}")}
                class="bg-cream aspect-[4/5] outline-primary relative block cursor-pointer overflow-hidden has-[:checked]:outline-3 has-[:checked]:outline-offset-2 has-[:focus-visible]:outline-2 has-[:focus-visible]:outline-offset-2"
              >
                <input
                  type="radio"
                  name={@variant[:own_photo_slug].name}
                  value={if index == 0, do: "", else: slug}
                  checked={if index == 0, do: is_nil(@own), else: @own == slug}
                  class="sr-only"
                />
                <span class="sr-only">{if index == 0, do: ~t"Main photo", else: ~t"Photo #{n = index + 1}"}</span>
                <.image src={slug} alt="" width={240} height={300} class="absolute inset-0 h-full w-full object-cover" />
                <.badge
                  :if={index == 0}
                  tone={:neutral}
                  icon="hero-star-solid"
                  class="[&_.hero-star-solid]:text-primary absolute top-1.5 left-1.5"
                >
                  {~t"Main"}
                </.badge>
              </label>
            </div>
          </fieldset>
          <p class="text-base-content/65 text-sm">{~t"Pick Main to follow whichever photo is main."}</p>
        </.drawer_body>
      </.admin_drawer>
    </li>
    """
  end

  attr :slug, :string, required: true
  attr :main?, :boolean, required: true

  defp size_thumbnail(assigns) do
    ~H"""
    <.image src={@slug} alt="" width={96} height={120} class="absolute inset-0 h-full w-full object-cover" />
    <%!-- The light glow keeps the star readable on dark photos. --%>
    <.icon
      :if={@main?}
      name="hero-star-solid"
      class="drop-shadow-[0_0_1.5px_rgb(255_255_255/0.9)] size-3.5 text-primary absolute top-1 left-1"
    />
    """
  end

  defp size_label(size) when size in [nil, ""], do: ~t"One size"
  defp size_label(size) when is_binary(size), do: size |> String.to_existing_atom() |> variant_size_label()
  defp size_label(size), do: variant_size_label(size)

  @impl true
  def handle_event("validate", %{"form" => params}, socket) do
    {:noreply, update(socket, :form, &AshPhoenix.Form.validate(&1, params))}
  end

  def handle_event("remove_photo", %{"slug" => slug}, socket),
    do: {:noreply, update_photos(socket, &List.delete(&1, slug))}

  def handle_event("make_main_photo", %{"slug" => slug}, socket),
    do: {:noreply, update_photos(socket, &[slug | List.delete(&1, slug)])}

  # Fills each size's stock with 0; nothing is saved until Jennie saves.
  def handle_event("mark_sold_out", _params, socket) do
    form = socket.assigns.form
    params = form.source.params

    sizes =
      for size <- form.source.forms[:product_variants] || [], into: %{} do
        key = size.name |> String.split(["[", "]"], trim: true) |> List.last()
        {key, Map.put(params["product_variants"][key] || %{}, "stock_quantity", "0")}
      end

    params = Map.put(params, "product_variants", Map.merge(params["product_variants"] || %{}, sizes))
    {:noreply, assign(socket, :form, AshPhoenix.Form.validate(form, params))}
  end

  def handle_event("add_variant", _params, socket) do
    {:noreply, update(socket, :form, &AshPhoenix.Form.add_form(&1, "form[product_variants]"))}
  end

  def handle_event("remove_variant", %{"path" => path}, socket) do
    {:noreply, update(socket, :form, &AshPhoenix.Form.remove_form(&1, path))}
  end

  def handle_event("translate", %{"from" => from}, socket),
    do: {:noreply, TranslationFields.translate(socket, from)}

  def handle_event("save", %{"form" => params}, socket) do
    case AshPhoenix.Form.submit(socket.assigns.form, params: params) do
      {:ok, _product} ->
        {:noreply,
         socket
         |> put_flash(:info, ~t"Product saved.")
         |> push_navigate(to: ~p"/admin/products")}

      {:error, form} ->
        {:noreply,
         socket
         |> assign(:form, form)
         |> put_flash(:error, ~t"The product wasn't saved. Check the fields marked below.")}
    end
  end

  @impl true
  def handle_async(:translate, result, socket),
    do: {:noreply, TranslationFields.put_translations(socket, result)}

  defp load_form(%{"id" => id}, actor) do
    case Ash.get(Product, id, actor: actor, load: [:product_variants, :sold_out?]) do
      {:ok, product} ->
        form = AshPhoenix.Form.for_update(product, :update, actor: actor) |> TranslationFields.add_forms()
        {:ok, product.name, to_form(form)}

      {:error, _} ->
        :error
    end
  end

  defp load_form(_params, actor) do
    form =
      AshPhoenix.Form.for_create(Product, :create, actor: actor)
      |> TranslationFields.add_forms()
      |> AshPhoenix.Form.add_form("form[product_variants]", validate?: false)

    {:ok, ~t"New product", to_form(form)}
  end

  # Each photo is stored as soon as it arrives, so sizes can pick it before the
  # product is saved. An abandoned form leaves its files behind.
  defp handle_photo_progress(:photos, %{done?: false}, socket), do: {:noreply, socket}

  defp handle_photo_progress(:photos, entry, socket) do
    slug = consume_uploaded_entry(socket, entry, &PhotoUpload.store_file(&1, entry))
    {:noreply, update_photos(socket, &(&1 ++ [slug]))}
  end

  defp update_photos(socket, fun) do
    form = socket.assigns.form
    slugs = fun.(photo_slugs(form))
    # From the whole form, as its own params miss the size a new form starts with.
    params = form |> AshPhoenix.Form.params() |> Map.put("photo_slugs", slugs)
    assign(socket, :form, AshPhoenix.Form.validate(form, params))
  end

  defp photo_slugs(form), do: form[:photo_slugs].value || []

  defp photo_upload_error(:too_many_files), do: ~t"Add at most #{count = @max_photos} photos."
  defp photo_upload_error(error), do: PhotoUpload.upload_error_message(error)
end
