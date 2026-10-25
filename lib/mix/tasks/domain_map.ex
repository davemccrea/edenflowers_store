defmodule Mix.Tasks.DomainMap do
  @moduledoc """
  Writes `tmp/domain-map/`: an `index.html` linking to one full-window page per
  diagram. There's an ER diagram of every Ash resource and how they relate, and
  Ash's class diagram of each domain. Paper-trail version resources are left
  out. Open it in a browser (it loads Mermaid from a CDN).

  ## Usage

      mix domain_map
  """
  use Mix.Task

  @shortdoc "Write an HTML map of the Ash domains"

  @dir "tmp/domain-map"

  @domain_colours %{
    "Accounts" => {"#dbeafe", "#1d4ed8"},
    "Catalog" => {"#dcfce7", "#15803d"},
    "Courses" => {"#fef3c7", "#b45309"},
    "Expenses" => {"#f3e8ff", "#7e22ce"},
    "Fulfillment" => {"#cffafe", "#0e7490"},
    "Orders" => {"#fee2e2", "#b91c1c"},
    "Payments" => {"#fce7f3", "#be185d"},
    "Pricing" => {"#e5e7eb", "#374151"}
  }

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.config")

    domains = Application.fetch_env!(:edenflowers, :ash_domains)
    all_resources = domains |> Enum.flat_map(&Ash.Domain.Info.resources/1) |> Enum.uniq()

    version_resources =
      for resource <- all_resources,
          AshPaperTrail.Resource in Spark.extensions(resource),
          into: MapSet.new(),
          do: AshPaperTrail.Resource.Info.version_resource(resource)

    resources = Enum.reject(all_resources, &(&1 in version_resources))

    app_sections = [
      {"overview", "Relationships",
       "Every resource and how they link. <code>||</code> exactly one, <code>|o</code> zero or one, <code>o{</code> zero or more. Labels are the relationship name.",
       er_diagram(resources, fields?: false), legend(domains)},
      {"fields", "Fields", "The same map with every attribute, private ones included.",
       er_diagram(resources, fields?: true), legend(domains)}
    ]

    domain_sections =
      domains
      |> Enum.map(fn domain ->
        name = domain |> Module.split() |> List.last()

        resource_names =
          domain
          |> Ash.Domain.Info.resources()
          |> Enum.reject(&(&1 in version_resources))
          |> Enum.map_join(", ", &(&1 |> inspect() |> String.replace_prefix("#{inspect(domain)}.", "")))

        diagram =
          domain
          |> Ash.Domain.Info.Diagram.mermaid_class_diagram()
          |> without_classes(Enum.filter(Ash.Domain.Info.resources(domain), &(&1 in version_resources)))

        {String.downcase(name), name, resource_names, diagram, ""}
      end)
      |> Enum.sort_by(&elem(&1, 1))

    File.rm_rf!(@dir)
    File.mkdir_p!(@dir)
    File.write!(Path.join(@dir, "index.html"), index_page(app_sections, domain_sections, resources))

    for {id, title, _intro, diagram, legend} <- app_sections ++ domain_sections do
      File.write!(Path.join(@dir, "#{id}.html"), diagram_page(title, diagram, legend))
    end

    Mix.shell().info("Wrote #{@dir}/index.html")
  end

  defp er_diagram(resources, fields?: fields?) do
    belongs_to_pairs =
      for resource <- resources,
          rel <- Ash.Resource.Info.relationships(resource),
          rel.type == :belongs_to,
          into: MapSet.new(),
          do: {resource, rel.destination}

    edges =
      for resource <- resources,
          rel <- Ash.Resource.Info.relationships(resource),
          rel.destination in resources,
          edge = edge(resource, rel, belongs_to_pairs),
          do: edge

    entities = Enum.map(resources, &entity(&1, fields?))

    class_defs =
      Enum.map(@domain_colours, fn {domain, {fill, stroke}} ->
        "    classDef #{domain} fill:#{fill},stroke:#{stroke},color:#111"
      end)

    Enum.join(["erDiagram" | entities ++ edges ++ class_defs], "\n")
  end

  # Ash's class diagram has no option to skip resources, so drop their class
  # blocks and lines from its text. Classes are named by short name, e.g. Version.
  defp without_classes(diagram, []), do: diagram

  defp without_classes(diagram, resources) do
    names = Enum.map(resources, &(&1 |> Ash.Resource.Info.short_name() |> to_string() |> Macro.camelize()))

    {lines, _skipping?} =
      diagram
      |> String.split("\n")
      |> Enum.reduce({[], false}, fn line, {lines, skipping?} ->
        trimmed = String.trim(line)

        cond do
          skipping? -> {lines, trimmed != "}"}
          Enum.any?(names, &(trimmed == "class #{&1} {")) -> {lines, true}
          Enum.any?(names, &(trimmed =~ ~r/(^#{&1} --|-- #{&1}$)/)) -> {lines, false}
          true -> {[line | lines], false}
        end
      end)

    lines |> Enum.reverse() |> Enum.join("\n")
  end

  defp legend(domains) do
    domains
    |> Enum.map(&(&1 |> Module.split() |> List.last()))
    |> Enum.sort()
    |> Enum.map_join(fn domain ->
      {fill, stroke} = Map.fetch!(@domain_colours, domain)
      ~s(<span style="background:#{fill};border:1px solid #{stroke}">#{domain}</span>)
    end)
  end

  # Drawn from the parent's side, so the label and the child's cardinality come
  # from the parent's has_many or has_one over the same key. A parent can have
  # several (Subscription has orders plus has_one booked_occurrence), and any
  # has_many means the child side is many.
  defp edge(resource, %{type: :belongs_to} = rel, _belongs_to_pairs) do
    inverses =
      rel.destination
      |> Ash.Resource.Info.relationships()
      |> Enum.filter(
        &(&1.type in [:has_many, :has_one] and &1.destination == resource and
            &1.destination_attribute == rel.source_attribute)
      )

    has_many = Enum.filter(inverses, &(&1.type == :has_many))
    parent = if rel.allow_nil?, do: "|o", else: "||"
    child = if inverses != [] and has_many == [], do: "o|", else: "o{"

    edge_line(rel.destination, parent <> "--" <> child, resource, label(rel, inverses, has_many))
  end

  defp edge(resource, %{type: :many_to_many} = rel, _belongs_to_pairs) do
    if resource < rel.destination, do: edge_line(resource, "}o--o{", rel.destination, rel.name)
  end

  # Otherwise a has_many or has_one is the inverse of a belongs_to drawn above
  defp edge(resource, rel, belongs_to_pairs) do
    unless MapSet.member?(belongs_to_pairs, {rel.destination, resource}) do
      cardinality = if rel.type == :has_many, do: "||--o{", else: "||--o|"
      edge_line(resource, cardinality, rel.destination, rel.name)
    end
  end

  defp label(rel, inverses, has_many) do
    case Enum.find(has_many, &is_nil(&1.filter)) || List.first(has_many) || List.first(inverses) do
      nil -> rel.name
      inverse -> inverse.name
    end
  end

  defp edge_line(from, cardinality, to, label),
    do: ~s(    #{node_id(from)} #{cardinality} #{node_id(to)} : "#{label}")

  defp entity(resource, false), do: entity_node(resource)

  defp entity(resource, true) do
    foreign_keys =
      for rel <- Ash.Resource.Info.relationships(resource),
          rel.type == :belongs_to,
          into: MapSet.new(),
          do: rel.source_attribute

    attributes =
      Enum.map(Ash.Resource.Info.attributes(resource), fn attribute ->
        key =
          cond do
            attribute.primary_key? -> " PK"
            attribute.name in foreign_keys -> " FK"
            true -> ""
          end

        "        #{type_name(attribute.type)} #{attribute.name}#{key}"
      end)

    Enum.join([entity_node(resource) <> " {" | attributes] ++ ["    }"], "\n")
  end

  # Coloured by domain, so the label can be the resource's own name
  defp entity_node(resource) do
    domain = resource |> Ash.Resource.Info.domain() |> Module.split() |> List.last()
    label = resource |> Module.split() |> List.last()
    ~s(    #{node_id(resource)}["#{label}"]:::#{domain})
  end

  defp node_id(resource), do: resource |> Module.split() |> Enum.join("_")

  defp type_name({:array, type}), do: type_name(type) <> "_array"
  defp type_name(type), do: type |> Module.split() |> List.last() |> String.replace(~r/[^A-Za-z0-9_]/, "_")

  defp index_page(app_sections, domain_sections, resources) do
    """
    <!doctype html>
    <html lang="en">
    <head>
    <meta charset="utf-8">
    <title>Eden Flowers Domain Map</title>
    <style>
      body { font-family: system-ui, sans-serif; max-width: 70ch; margin: 0 auto; padding: 16px; line-height: 1.6; }
    </style>
    </head>
    <body>
      <h1>Eden Flowers domain map</h1>
      <p>Generated by <code>just map-domains</code> on #{Date.utc_today()}. #{length(resources)} resources.</p>
      <h2>Whole app</h2>
      <p>One ER diagram of every resource across the domains.</p>
      <ul>#{links(app_sections)}</ul>
      <h2>By domain</h2>
      <p>Each domain's resources with their public attributes and actions.</p>
      <ul>#{links(domain_sections)}</ul>
    </body>
    </html>
    """
  end

  defp links(sections) do
    Enum.map_join(sections, fn {id, title, intro, _diagram, _legend} ->
      ~s(<li><a href="#{id}.html">#{title}</a>: #{intro}</li>)
    end)
  end

  defp diagram_page(title, diagram, legend) do
    """
    <!doctype html>
    <html lang="en">
    <head>
    <meta charset="utf-8">
    <title>#{title}: Eden Flowers</title>
    <style>
      html, body, pre { margin: 0; height: 100%; }
      .legend { position: fixed; top: 8px; left: 8px; display: flex; gap: 4px; font: 12px system-ui, sans-serif; }
      .legend span { padding: 2px 6px; border-radius: 3px; }
    </style>
    </head>
    <body>
    <div class="legend">#{legend}</div>
    <pre class="mermaid">#{Phoenix.HTML.html_escape(diagram) |> Phoenix.HTML.safe_to_string()}</pre>
    <script src="https://cdn.jsdelivr.net/npm/svg-pan-zoom@3.6.1/dist/svg-pan-zoom.min.js"></script>
    <script type="module">
      import mermaid from "https://cdn.jsdelivr.net/npm/mermaid@11.17.2/dist/mermaid.esm.min.mjs";
      import elkLayouts from "https://cdn.jsdelivr.net/npm/@mermaid-js/layout-elk@0.2.3/dist/mermaid-layout-elk.esm.min.mjs";
      mermaid.registerLayoutLoaders(elkLayouts);
      mermaid.initialize({ startOnLoad: false, layout: "elk" });
      await mermaid.run();

      const svg = document.querySelector("svg");
      svg.style.maxWidth = "none";
      svg.setAttribute("width", "100%");
      svg.setAttribute("height", "100%");
      svgPanZoom(svg, { controlIcons: true, zoomScaleSensitivity: 0.3, maxZoom: 20 });
    </script>
    </body>
    </html>
    """
  end
end
