namespace Demo.LogicApps.Tests;

using System.Xml.Linq;
using DotLiquid;
using Newtonsoft.Json;
using FluentAssertions;

public class SourceToTargetMapTests
{
    [Theory]
    [InlineData(@"TestData\SourceToTargetMapTests\Input.xml", 
                @"TestData\SourceToTargetMapTests\Expected_Output.json", 
                @"..\..\..\..\..\Transforms\source-to-target-map.liquid")]
    public void TestMap_Success(string inputFile, string expectedOutputFile, string liquidTransformFile)
    {
        // Arrange
        var xDocument = XDocument.Parse(File.ReadAllText(inputFile));
        Dictionary<string, object> xmlInput = (Dictionary<string, object>)FlattenXmlToDictionary(xDocument.Root, "content");

        var jsonExpectedOutput = File.ReadAllText(expectedOutputFile);

        // Need to replace the Liquid replace-reference to just 'content', as it seems the DotLiquid library doesn't like having a '.'
        // This apparently works a bit different in LogicApps
        string liquidTemplateContent = File.ReadAllText(liquidTransformFile).Replace("content.DemoIncomingMessage", "content");
        var liquidTemplate = Template.Parse(liquidTemplateContent);

        // Act
        string jsonOutputFromLiquidTransform = liquidTemplate.Render(Hash.FromDictionary(xmlInput));

        // Assert
        AreJsonStringsEqual(jsonOutputFromLiquidTransform, jsonExpectedOutput).Should().BeTrue();
    }

    [Theory]
    [InlineData(@"TestData\SourceToTargetMapTests\Input.xml", 
                @"TestData\SourceToTargetMapTests\Failed_Expected_Output.json", 
                @"..\..\..\..\..\Transforms\source-to-target-map.liquid")]
    public void TestMap_Fail(string inputFile, string expectedOutputFile, string liquidTransformFile)
    {
        // Arrange
        var xDocument = XDocument.Parse(File.ReadAllText(inputFile));
        Dictionary<string, object> xmlInput = (Dictionary<string, object>)FlattenXmlToDictionary(xDocument.Root, "content");

        var jsonExpectedOutput = File.ReadAllText(expectedOutputFile);

        // Need to replace the Liquid replace-reference to just 'content', as it seems the DotLiquid library doesn't like having a '.'
        // This apparently works a bit different in LogicApps
        string liquidTemplateContent = File.ReadAllText(liquidTransformFile).Replace("content.DemoIncomingMessage", "content");
        var liquidTemplate = Template.Parse(liquidTemplateContent);

        // Act
        string jsonOutputFromLiquidTransform = liquidTemplate.Render(Hash.FromDictionary(xmlInput));

        // Assert
        AreJsonStringsEqual(jsonOutputFromLiquidTransform, jsonExpectedOutput).Should().BeFalse();
    }

    /// <summary>
    /// Convert the XML message into a dictionary of values
    /// </summary>
    /// <param name="xElement"></param>
    /// <param name="prefix"></param>
    /// <returns></returns>
    static IDictionary<string, object> FlattenXmlToDictionary(XElement xElement, string prefix = "")
    {
        var dict = new Dictionary<string, object>();

        foreach (var element in xElement.Elements())
        {
            dict[element.Name.ToString()] = element.HasElements ? 
                FlattenXmlToDictionary(element, element.Name.ToString() + ".") : 
                element.Value;
        }

        return new Dictionary<string, object> { { prefix.TrimEnd('.'), dict } };
    }

    /// <summary>
    /// Utility to compare two JSON strings who might differ in formatting but represent the same data
    /// </summary>
    /// <param name="json1"></param>
    /// <param name="json2"></param>
    /// <returns></returns>
    static bool AreJsonStringsEqual(string json1, string json2)
    {
        object obj1 = JsonConvert.DeserializeObject(json1);
        object obj2 = JsonConvert.DeserializeObject(json2);

        string normalizedJson1 = JsonConvert.SerializeObject(obj1);
        string normalizedJson2 = JsonConvert.SerializeObject(obj2);

        return normalizedJson1 == normalizedJson2;
    }
}
