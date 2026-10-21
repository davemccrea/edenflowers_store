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
        <.admin_page_header title={@page_title} back={{~t"Products", ~p"/admin/products"}}>
          <:subtitle :if={@form.source.type == :update}>
            <span id="product-status" class="inline-flex flex-wrap items-center gap-1.5">
              <.badge :if={@form.source.data.draft} tone={:neutral}>{~t"Draft"}</.badge>
              <.badge :if={!@form.source.data.draft} tone={:success}>{~t"Published"}</.badge>
              <.badge :if={@form.source.data.sold_out?} tone={:warning}>{~t"Sold out"}</.badge>
            </span>
          </:subtitle>
          <:actions>
            <.button
              :if={@form.source.type == :update && !@form.source.data.draft}
              href={~q"/#{language}/product/#{@form.source.data.id}"}
              target="_blank"
              variant="secondary"
              size="sm"
            >
              <.icon name="hero-arrow-top-right-on-square" class="h-4 w-4" /> {~t"View in store"}
            </.button>
            <.button type="submit" form="product-form" variant="primary" size="sm" phx-disable-with={~t"Saving…"}>
              {~t"Save"}
            </.button>
          </:actions>
        </.admin_page_header>

        <.form
          for={@form}
          id="product-form"
          data-warn-unsaved={~t"You have unsaved changes. Leave without saving?"}
          phx-change="validate"
          phx-submit="save"
          class="grid grid-cols-1 gap-6 xl:grid-cols-[minmax(0,1fr)_24rem] xl:items-start"
        >
          <div class="space-y-6">
            <.form_section title={~t"Name and description"}>
              <.language_fields form={@form} translating={@translating} />
            </.form_section>

            <.form_section title={~t"Sizes and prices"}>
              <:description>{~t"A size shows the main photo unless you pick another."}</:description>
              <ul class="border-base-content/12 divide-base-content/8 divide-y border">
                <.inputs_for :let={variant} field={@form[:product_variants]}>
                  <li class="space-y-3 p-4">
                    <div class="min-w-0 space-y-3 min-[1800px]:flex min-[1800px]:items-end min-[1800px]:gap-6 min-[1800px]:space-y-0">
                      <div class="grid grid-cols-1 gap-3 min-[1800px]:flex-1 sm:grid-cols-3">
                        <.input
                          field={variant[:size]}
                          type="select"
                          label={~t"Size"}
                          prompt={~t"One size"}
                          options={Enum.map(ProductVariantSize.values(), &{variant_size_label(&1), &1})}
                          class="select w-full"
                        />
                        <.input
                          field={variant[:price]}
                          type="text"
                          inputmode="decimal"
                          label={~t"Price (€)"}
                          class="input w-full tabular-nums"
                        />
                        <%!-- ponytail: saving sends the count shown when the form opened, so a sale made
                             meanwhile is undone and may oversell later. Send only changed counts if that bites. --%>
                        <.input
                          field={variant[:stock_quantity]}
                          type="number"
                          min="0"
                          label={~t"In stock"}
                          placeholder={~t"Unlimited"}
                          class="input w-full tabular-nums"
                        />
                      </div>
                      <div class="flex flex-wrap items-center gap-x-6 gap-y-2 min-[1800px]:shrink-0 min-[1800px]:flex-nowrap">
                        <.input field={variant[:draft]} type="checkbox" label={~t"Draft"} />
                        <.button
                          type="button"
                          phx-click="remove_variant"
                          phx-value-path={variant.name}
                          variant="destructive"
                          size="sm"
                          class="ml-auto"
                        >
                          {~t"Remove"}
                        </.button>
                      </div>
                    </div>
                    <.size_photo_picker
                      field={variant[:own_photo_slug]}
                      photo_slugs={photo_slugs(@form)}
                      show_errors={@form.source.submitted_once?}
                    />
                  </li>
                </.inputs_for>
                <li>
                  <button
                    type="button"
                    phx-click="add_variant"
                    class="text-base-content/80 flex w-full items-center gap-2 p-4 text-sm font-medium transition-colors hover:bg-base-200/60 hover:text-base-content"
                  >
                    <.icon name="hero-plus" class="h-4 w-4" />
                    {~t"Add size"}
                  </button>
                </li>
              </ul>
              <div class="mt-3 flex flex-wrap items-end justify-between gap-4">
                <div class="w-full sm:w-64">
                  <.input
                    field={@form[:tax_rate_id]}
                    type="select"
                    label={~t"VAT"}
                    options={Enum.map(@tax_rates, &{&1.name, &1.id})}
                    class="select w-full"
                  />
                </div>
                <.button type="button" phx-click="mark_sold_out" variant="secondary" size="sm" data-testid="mark-sold-out">
                  {~t"Mark every size sold out"}
                </.button>
              </div>
            </.form_section>
          </div>

          <aside class="flex flex-col gap-6 xl:row-span-2">
            <.form_section title={~t"Photos"}>
              <:description>{~t"Up to #{count = @max_photos}. The main photo shows in the store's listings."}</:description>
              <.photo_gallery
                field={@form[:photo_slugs]}
                photo_slugs={photo_slugs(@form)}
                upload={@uploads.photos}
                max={@max_photos}
                show_errors={@form.source.submitted_once?}
              />
            </.form_section>

            <.form_section title={~t"In the store"}>
              <div class="space-y-4">
                <div class="grid grid-cols-1 gap-4">
                  <.input
                    field={@form[:product_category_id]}
                    type="select"
                    label={~t"Category"}
                    prompt={~t"Choose a category"}
                    options={Enum.map(@categories, &{&1.name, &1.id})}
                    class="select w-full"
                  />
                  <.input
                    field={@form[:position]}
                    type="number"
                    min="0"
                    label={~t"Position in store (0 = first)"}
                    class="input max-w-48 w-full tabular-nums"
                  />
                </div>
                <div>
                  <.input field={@form[:draft]} type="checkbox" label={~t"Draft"} />
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

          <%!-- After the aside so its fields sit above Save once stacked. --%>
          <.button
            type="submit"
            variant="primary"
            phx-disable-with={~t"Saving…"}
            class="w-full sm:w-auto sm:justify-self-start xl:col-start-1"
          >
            {~t"Save product"}
          </.button>
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
    <ul id="product-photos" class="grid grid-cols-3 gap-3">
      <li :for={{slug, index} <- Enum.with_index(@photo_slugs)} data-testid="product-photo">
        <input type="hidden" name={@field.name <> "[]"} value={slug} />
        <span class="bg-cream aspect-[4/5] relative block overflow-hidden">
          <.image src={slug} alt="" width={240} height={300} class="absolute inset-0 h-full w-full object-cover" />
          <.badge :if={index == 0} tone={:neutral} class="absolute top-1.5 left-1.5">{~t"Main"}</.badge>
        </span>
        <span class="mt-1.5 flex flex-wrap gap-x-3 text-sm">
          <button
            :if={index > 0}
            type="button"
            phx-click="make_main_photo"
            phx-value-slug={slug}
            class="link-underline-static-body"
          >
            {~t"Make main"}
          </button>
          <%!-- A product always has a photo, so the last one is replaced rather than removed. --%>
          <button
            :if={length(@photo_slugs) > 1}
            type="button"
            phx-click="remove_photo"
            phx-value-slug={slug}
            class="link-underline-static-body"
          >
            {~t"Remove"}
          </button>
        </span>
      </li>
      <li :for={entry <- @upload.entries}>
        <span class="bg-cream aspect-[4/5] relative block overflow-hidden">
          <.live_img_preview entry={entry} class="absolute inset-0 h-full w-full object-cover opacity-60" />
        </span>
        <progress value={entry.progress} max="100" class="progress mt-1.5 h-1 w-full">{entry.progress}%</progress>
      </li>
      <li :if={length(@photo_slugs) + length(@upload.entries) < @max}>
        <label
          phx-drop-target={@upload.ref}
          class="group outline-primary block has-[:focus-visible]:outline-2 has-[:focus-visible]:outline-offset-2"
        >
          <span class="border-base-content/25 text-cream-content/70 bg-cream aspect-[4/5] flex flex-col items-center justify-center gap-1.5 border border-dashed transition-colors group-hover:border-base-content/50">
            <.icon name="hero-plus" class="size-6" />
            <span class="px-2 text-center text-sm">{~t"Add photos"}</span>
          </span>
          <.live_file_input upload={@upload} class="sr-only" />
        </label>
      </li>
    </ul>
    <p :for={err <- @upload_errors} class="text-error mt-1.5 text-sm">{photo_upload_error(err)}</p>
    <.error :for={msg <- Enum.map(@errors, &translate_error/1)}>{msg}</.error>
    """
  end

  attr :field, Phoenix.HTML.FormField, required: true
  attr :photo_slugs, :list, required: true
  attr :show_errors, :boolean, required: true

  # A size whose photo was just removed from the gallery shows as "Main photo",
  # which is what saving gives it.
  defp size_photo_picker(assigns) do
    assigns =
      assign(assigns,
        own: Enum.find(assigns.photo_slugs, &(&1 == assigns.field.value)),
        errors: if(assigns.show_errors, do: assigns.field.errors, else: [])
      )

    ~H"""
    <fieldset>
      <legend class="text-base-content/80 mb-1.5 text-sm">{~t"Photo"}</legend>
      <div class="flex flex-wrap gap-2">
        <label class="outline-primary border-base-content/25 flex h-12 cursor-pointer items-center border px-3 text-sm has-[:checked]:outline-2 has-[:checked]:outline-offset-1 has-[:focus-visible]:outline-2 has-[:focus-visible]:outline-offset-2">
          <input type="radio" name={@field.name} value="" checked={is_nil(@own)} class="sr-only" />
          {~t"Main photo"}
        </label>
        <label
          :for={{slug, index} <- Enum.with_index(@photo_slugs, 1)}
          class="outline-primary bg-cream aspect-[4/5] relative block h-12 cursor-pointer overflow-hidden has-[:checked]:outline-2 has-[:checked]:outline-offset-1 has-[:focus-visible]:outline-2 has-[:focus-visible]:outline-offset-2"
        >
          <input type="radio" name={@field.name} value={slug} checked={@own == slug} class="sr-only" />
          <span class="sr-only">{~t"Photo #{index}"}</span>
          <.image src={slug} alt="" width={80} height={100} class="absolute inset-0 h-full w-full object-cover" />
        </label>
      </div>
      <.error :for={msg <- Enum.map(@errors, &translate_error/1)}>{msg}</.error>
    </fieldset>
    """
  end

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
