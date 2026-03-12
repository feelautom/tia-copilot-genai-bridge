using System;
using System.Collections.Generic;
using System.Linq;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text;
using System.Threading.Tasks;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using TiaPortalApi.Core.DTOs;

namespace TiaPortalApi.Core.Services.Assistant.Providers
{
    public class OpenAiProvider : ILLMProvider
    {
        private readonly HttpClient _httpClient;
        private const string DefaultBaseUrl = "https://api.openai.com/v1";

        public OpenAiProvider()
        {
            _httpClient = new HttpClient();
            _httpClient.Timeout = TimeSpan.FromSeconds(90);
        }

        public string Name => "OpenAI";

        private string GetBaseUrl(AssistantSettings settings)
        {
            if (string.IsNullOrEmpty(settings.CustomEndpoint))
                return DefaultBaseUrl;

            return settings.CustomEndpoint.TrimEnd('/');
        }

        public async Task<AssistantResponse> ChatAsync(AssistantSettings settings, List<object> messages, IEnumerable<object> tools)
        {
            if (string.IsNullOrEmpty(settings.ApiKey)) return new AssistantResponse { Success = false, ErrorMessage = "OpenAI API Key is missing." };

            string requestBody = JsonConvert.SerializeObject(new
            {
                model = string.IsNullOrEmpty(settings.Model) ? "gpt-4o" : settings.Model,
                messages = messages,
                tools = tools,
                tool_choice = "auto",
                temperature = 0.7,
                max_tokens = 4096
            }, new JsonSerializerSettings { NullValueHandling = NullValueHandling.Ignore });

            HttpResponseMessage response = null;
            string content = null;
            int maxRetries = 3;
            int currentRetry = 0;

            try
            {
                string baseUrl = GetBaseUrl(settings);
                while (currentRetry <= maxRetries)
                {
                    var request = new HttpRequestMessage(HttpMethod.Post, $"{baseUrl}/chat/completions");
                    request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", settings.ApiKey);
                    request.Content = new StringContent(requestBody, Encoding.UTF8, "application/json");

                    response = await _httpClient.SendAsync(request);
                    content = await response.Content.ReadAsStringAsync();

                    int statusCode = (int)response.StatusCode;
                    if (statusCode == 429 || statusCode == 503 || statusCode == 529)
                    {
                        currentRetry++;
                        if (currentRetry > maxRetries) break;

                        int delaySeconds = currentRetry * 15; // 15s, 30s, 45s backoff
                        if (response.Headers.Contains("retry-after"))
                        {
                            var retryAfter = response.Headers.GetValues("retry-after").FirstOrDefault();
                            if (int.TryParse(retryAfter, out int parsed)) delaySeconds = parsed + 1;
                        }
                        await Task.Delay(delaySeconds * 1000);
                        continue;
                    }
                    break;
                }

                if (!response.IsSuccessStatusCode)
                {
                    return new AssistantResponse { Success = false, ErrorMessage = $"OpenAI Error ({response.StatusCode}): {content}" };
                }

                var json = JObject.Parse(content);
                var choice = json["choices"]?[0];
                var aiMessage = choice?["message"];
                var finishReason = choice?["finish_reason"]?.ToString();

                return new AssistantResponse
                {
                    Success = true,
                    Content = aiMessage["content"]?.ToString(),
                    RawData = aiMessage,
                    FinishReason = finishReason
                };
            }
            catch (TaskCanceledException)
            {
                return new AssistantResponse { Success = false, ErrorMessage = "OpenAI timeout: the model took too long to respond. Try a simpler request or a faster model." };
            }
            catch (Exception ex)
            {
                return new AssistantResponse { Success = false, ErrorMessage = "OpenAI Exception: " + ex.Message };
            }
        }

        public async Task<IEnumerable<string>> GetModelsAsync(AssistantSettings settings)
        {
            var hardcodedModels = new List<string>
            {
                "gpt-4o",
                "gpt-4o-mini",
                "o3-mini"
            };

            if (string.IsNullOrEmpty(settings.ApiKey)) return hardcodedModels;

            try
            {
                string baseUrl = GetBaseUrl(settings);
                var request = new HttpRequestMessage(HttpMethod.Get, $"{baseUrl}/models");
                request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", settings.ApiKey);

                var response = await _httpClient.SendAsync(request);
                if (!response.IsSuccessStatusCode) return hardcodedModels;

                var content = await response.Content.ReadAsStringAsync();
                var json = JObject.Parse(content);
                var models = json["data"] as JArray;

                if (models == null) return hardcodedModels;

                // Si c'est un endpoint custom (OVH, etc.), on prend tous les modèles dispo
                bool isCustom = !string.IsNullOrEmpty(settings.CustomEndpoint);

                var dynamicList = models
                    .Select(m => m["id"]?.ToString())
                    .Where(id => !string.IsNullOrEmpty(id))
                    .Where(id => isCustom || (id.StartsWith("gpt-", StringComparison.OrdinalIgnoreCase) || id.StartsWith("o1", StringComparison.OrdinalIgnoreCase)))
                    .OrderByDescending(id => id)
                    .ToList();

                return dynamicList.Count > 0 ? dynamicList : hardcodedModels;
            }
            catch
            {
                return hardcodedModels;
            }
        }
    }
}
