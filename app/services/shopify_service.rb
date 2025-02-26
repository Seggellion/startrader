# app/services/shopify_service.rb

class ShopifyService
  def initialize
    shop_url = Setting.get('shopify_shop_url')
    storefront_access_token = Setting.get('shopify_storefront_access_token')

    @client = ShopifyAPI::Clients::Graphql::Storefront.new(
      shop_url, 
      private_token: storefront_access_token
    )

    verify_permissions
  end

  def verify_permissions
    query = <<-GRAPHQL
      {
        shop {
          name
        }
      }
    GRAPHQL

    response = @client.query(query: query)
    if response.code == 200 && response.body["data"]
      puts "Shopify Storefront API connection successful. Shop Name: #{response.body['data']['shop']['name']}"
    else
      raise "ACCESS_DENIED: Ensure the access token has the required permissions."
    end
  end

  def fetch_products
    query = <<-GRAPHQL
    {
      products(first: 20) {
        edges {
          node {
            id
            title
            handle
            variants(first: 3) {
              edges {
                node {
                  id
                  title
                  price {
                    amount
                    currencyCode
                  }
                  image {
                    src: transformedSrc
                    altText
                  }
                }
              }
            }
          }
        }
      }
    }
  GRAPHQL

    response = @client.query(query: query)
    
    if response.body["errors"].present?
      raise "GraphQL Error: #{response.body['errors']}"
    end

    response.body["data"]["products"]["edges"]
  end

  def fetch_product_by_handle(handle)
    query = <<-GRAPHQL
    {
      productByHandle(handle: "#{handle}") {
        id
        title
        handle
        descriptionHtml
        images(first: 10) {
          edges {
            node {
              src
              altText
            }
          }
        }
        variants(first: 100) {
          edges {
            node {
              id
              title
              price {
                amount
                currencyCode
              }
              image {
                src
                altText
              }
            }
          }
        }
      }
    }
  GRAPHQL
  
    response = @client.query(query: query)
    
    if response.body["errors"].present?
      raise "GraphQL Error: #{response.body['errors']}"
    end
  
    response.body["data"]["productByHandle"]
  end

  
  def create_cart
    query = <<-GRAPHQL
      mutation {
        cartCreate(input: {}) {
          cart {
            id
          }
        }
      }
    GRAPHQL

    response = @client.query(query: query)
    response.body["data"]["cartCreate"]["cart"]
  end

  def add_to_cart(cart_id, variant_id)
    query = <<-GRAPHQL
      mutation {
        cartLinesAdd(cartId: "#{cart_id}", lines: [{quantity: 1, merchandiseId: "#{variant_id}"}]) {
          cart {
            id
            lines(first: 10) {
              edges {
                node {
                  quantity
                  merchandise {
                    ... on ProductVariant {
                      id
                      title
                      price {
                        amount
                        currencyCode
                      }
                      product {
                        title
                        handle
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    GRAPHQL

    response = @client.query(query: query)
    response.body["data"]["cartLinesAdd"]["cart"]
  end

  def remove_from_cart(cart_id, line_id)
    query = <<-GRAPHQL
      mutation {
        cartLinesRemove(cartId: "#{cart_id}", lineIds: ["#{line_id}"]) {
          cart {
            id
            lines(first: 10) {
              edges {
                node {
                  id
                  quantity
                  merchandise {
                    ... on ProductVariant {
                      id
                      title
                      price {
                        amount
                        currencyCode
                      }
                      product {
                        title
                        handle
                        featuredImage {
                          url
                          altText
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    GRAPHQL

    response = @client.query(query: query)

    response.body["data"]["cartLinesRemove"]["cart"]
  end

  def fetch_cart(cart_id)
    query = <<-GRAPHQL
      {
        cart(id: "#{cart_id}") {
          id
          checkoutUrl
          lines(first: 10) {
            edges {
              node {
                id
                quantity
                merchandise {
                  ... on ProductVariant {
                    id
                    title
                    price {
                      amount
                      currencyCode
                    }
                    product {
                      title
                      handle
                      featuredImage {
                        url
                        altText
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    GRAPHQL
  
    response = @client.query(query: query)
    response.body["data"]["cart"]
  end
end
