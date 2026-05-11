using Microsoft.AspNetCore.Http;
using Shared.Models.Base;
using Shared.Models.Events;
using Shared.Models.Module;
using Shared.Models.Module.Interfaces;
using Shared.Models.Online.Settings;
using Shared.Services;
using System.Collections.Generic;

namespace Kinoflix;

public class ModInit : IModuleLoaded, IModuleOnline
{
    public static OnlinesSettings conf;

    public List<ModuleOnlineItem> Invoke(HttpContext httpContext, RequestModel requestInfo, string host, OnlineEventsModel args)
    {
        var online = new List<ModuleOnlineItem>();
        bool iscn = args.original_language is "ja" or "ko" or "zh" or "cn";

        if (args.kinopoisk_id > 0 && !iscn)
            online.Add(new(conf, arg_title: " (Грузинский)"));

        return online;
    }

    public void Loaded(InitspaceModel baseconf)
    {
        updateConf();
        EventListener.UpdateInitFile += updateConf;
        EventListener.OnlineApiQuality += onlineApiQuality;
    }

    public void Dispose()
    {
        EventListener.UpdateInitFile -= updateConf;
        EventListener.OnlineApiQuality -= onlineApiQuality;
    }

    void updateConf()
    {
        conf = ModuleInvoke.Init("Kinoflix", new OnlinesSettings("Kinoflix", "https://kinoflix.tv", streamproxy: true)
        {
            displayindex = 900,
            rch_access = "apk",
            stream_access = "apk",
            rchstreamproxy = "web,cors",
            headers_stream = HeadersModel.Init(Http.defaultFullHeaders,
                ("referer", "https://kinoflix.tv"),
                ("sec-fetch-dest", "empty"),
                ("sec-fetch-mode", "cors"),
                ("sec-fetch-site", "cross-site")
            ).ToDictionary()
        });
    }

    string onlineApiQuality(EventOnlineApiQuality e)
    {
        return e.balanser == "kinoflix" ? " ~ 1080p" : null;
    }
}
