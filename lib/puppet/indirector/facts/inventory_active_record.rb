require 'puppet/rails'
require 'puppet/rails/inventory_node'
require 'puppet/rails/inventory_fact'
require 'puppet/indirector/active_record'
require 'puppet/util/retryaction'

class Puppet::Node::Facts::InventoryActiveRecord < Puppet::Indirector::ActiveRecord
  def find(request)
    node = Puppet::Rails::InventoryNode.find_by_name(request.key)
    return nil unless node
    facts = Puppet::Node::Facts.new(node.name, node.facts_to_hash)
    facts.timestamp = node.timestamp
    facts
  end

  def save(request)
    Puppet::Util::RetryAction.retry_action :retries => 4, :retry_exceptions => {ActiveRecord::StatementInvalid => 'MySQL Error.  Retrying'} do
      facts = request.instance
      node = Puppet::Rails::InventoryNode.find_by_name(request.key) || Puppet::Rails::InventoryNode.create(:name => request.key, :timestamp => facts.timestamp)
      node.timestamp = facts.timestamp

      ActiveRecord::Base.transaction do
        Puppet::Rails::InventoryFact.delete_all(:node_id => node.id)
        # We don't want to save internal values as facts, because those are
        # metadata that belong on the node
        facts.values.each do |name,value|
          next if name.to_s =~ /^_/
          node.facts.build(:name => name, :value => value)
        end
        node.save
      end
    end
  end

  def search(request)
    return [] unless request.options

    fact_filters = Hash.new {|h,k| h[k] = []}
    meta_filters = Hash.new {|h,k| h[k] = []}

    if q_json = request.options[:q]
      # When q is specified, it uses a json packed query format
      q = JSON.parse(q_json)
      q.each do |type,queries|
        queries.each do |query|
          operator = query['comp']
          name = query['name']
          value = query['val']
          if type == 'facts'
            fact_filters[operator] << [name,value]
          elsif type == 'meta' and name == 'timestamp'
            meta_filters[operator] << [name,value]
          end
        end
      end
    else
      # Otherwise we fall back to the old mechanism
      request.options.each do |key,value|
        type, name, operator = key.to_s.split(".")
        operator ||= "eq"
        if type == "facts"
          fact_filters[operator] << [name,value]
        elsif type == "meta" and name == "timestamp"
          meta_filters[operator] << [name,value]
        end
      end
    end

    puts fact_filters.inspect

    matching_nodes = nodes_matching_fact_filters(fact_filters) + nodes_matching_meta_filters(meta_filters)

    # to_a because [].inject == nil
    nodes = matching_nodes.inject {|nodes,this_set| nodes & this_set}.to_a.sort
  end

  private

  def nodes_matching_fact_filters(fact_filters)
    node_sets = []

    require 'facter/util/query'

    # In this case we are just being passed a single fact, so do a normal
    # search
    fact_filters['eq'].each do |name,value|
      query = Facter::Util::Query.new(name)

      if query.is_flat?
        node_sets << Puppet::Rails::InventoryNode.has_fact_with_value(name,value).map {|node| node.name}
      else
        node_sets << structured_fact_search(query, '==', value)
      end
    end
    fact_filters['ne'].each do |name,value|
      query = Facter::Util::Query.new(name)

      if query.is_flat?
        node_sets << Puppet::Rails::InventoryNode.has_fact_without_value(name,value).map {|node| node.name}
      else
        node_sets << structured_fact_search(query, '!=', value)
      end
    end
    {
      'gt' => '>',
      'lt' => '<',
      'ge' => '>=',
      'le' => '<='
    }.each do |operator_name,operator|
      fact_filters[operator_name].each do |name,value|
        query = Facter::Util::Query.new(name)

        if query.is_flat?
          facts = Puppet::Rails::InventoryFact.find_by_sql(
            ["SELECT inventory_facts.value, inventory_nodes.name AS node_name
              FROM inventory_facts INNER JOIN inventory_nodes
              ON inventory_facts.node_id = inventory_nodes.id
              WHERE inventory_facts.name = ?", name])
          node_sets << facts.select {|fact| fact.value.to_f.send(operator, value.to_f)}.map {|fact| fact.node_name}
        else
          node_sets << structured_fact_search(query, operator, value)
        end
      end
    end
    node_sets
  end

  def structured_fact_search(query, operator, value)
    # First break up the query and grab the top fact, we'll use that in the SQL
    # search
    dquery = query.decomposed_query
    top_fact = dquery[0]

    initial_set = Puppet::Rails::InventoryNode.has_fact(top_fact)

    # Run it through the facter search and collect the node names where the
    # match occurred
    initial_set.collect do |node|
      if operator == '!='
        # Work around the absence of != method in Ruby 1.8.x
        node.name unless query.search_facts(node.facts_to_hash) == value
      else
        node.name if query.search_facts(node.facts_to_hash).send(operator, value)
      end
    end.compact
  end

  def nodes_matching_meta_filters(meta_filters)
    node_sets = []
    {
      'eq' => '=',
      'ne' => '!=',
      'gt' => '>',
      'lt' => '<',
      'ge' => '>=',
      'le' => '<='
    }.each do |operator_name,operator|
      meta_filters[operator_name].each do |name,value|
        node_sets << Puppet::Rails::InventoryNode.find(:all, :select => "name", :conditions => ["timestamp #{operator} ?", value]).map {|node| node.name}
      end
    end
    node_sets
  end
end
