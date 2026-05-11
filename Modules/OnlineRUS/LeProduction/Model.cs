namespace LeProduction;

class LeProductionEpisode
{
    public int season { get; set; }
    public int episode { get; set; }
    public string comment { get; set; }
    public string file { get; set; }
}

class LeProductionSearchItem
{
    public int season { get; set; }
    public string href { get; set; }
    public string title { get; set; }
}
