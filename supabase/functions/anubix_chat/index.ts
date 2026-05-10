import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const incomingData = await req.json()
    console.log("Received from client:", incomingData);
    
    const OMNILINK_API_KEY = "Bearer olink_Y7moAqrI3XhoSJNnB9fbeQWN";
    
    const requestBody = JSON.stringify({
      "prompt": incomingData.prompt ? incomingData.prompt : JSON.stringify(incomingData),
      "agentName": "ANUBIX"
    });

    const response = await fetch("https://www.omnilink-agents.com/api/chat", {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': OMNILINK_API_KEY
      },
      body: requestBody
    });

    const data = await response.json();

    return new Response(JSON.stringify(data), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: response.status,
    })
    
  } catch (error: any) {
    return new Response(JSON.stringify({ error: error.message }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 500,
    })
  }
})