<?xml version="1.0" encoding="UTF-8"?>
<!--
     call-app.xsl
     Create Application Descriptions for each Vortex App

     Jurgen Hildebrand (Jurgen.Hildebrand@ing.com)
-->
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
                xmlns:xs="http://www.w3.org/2001/XMLSchema"
                xmlns:fn="urn:xmlast:functions"
                xmlns:l="urn:xmlast:lineage"
                xmlns:r="urn:xmlast:graph"
                xmlns:m="urn:git:metadata"
                exclude-result-prefixes="xs fn" expand-text="yes" version="3.0">

    <xsl:param name="work-uri"/>
    <xsl:param name="output-ext">xml</xsl:param>

    <xsl:output method="xml" indent="yes"/>
    <xsl:strip-space elements="*"/>
    <!--
    Top Level Match Rule
    -->
    <xsl:template match="/*">
        <xsl:variable name="db-names" select="distinct-values(//database/@name)"/>
        <xsl:message>db-names: {$db-names}</xsl:message>
        <xsl:message>schema-names: {$schema-names}</xsl:message>
        <xsl:element name="{local-name(.)}">
            <xsl:apply-templates select="@*|node()"/>
        </xsl:element>
    </xsl:template>

    <!--
    Handle processors
    -->
    <xsl:template match="applicationcomponent[app]">
        <xsl:variable name="name" select="lower-case(replace(@name,' ','-'))"/>
        <xsl:variable name="app-path">{$work-uri}/lineage/app/xml/{$name}.{$output-ext}</xsl:variable>
        <xsl:message>generating: {$name} {$app-path}</xsl:message>
        <applicationcomponent path="{$app-path}">
            <xsl:copy-of select="@*,doc,properties"/>
        </applicationcomponent>
        <xsl:variable name="tree">
            <xsl:apply-templates select="app/(* except distributions),app/distributions"/>
        </xsl:variable>
        <xsl:variable name="java-namespace-bindings" as="element(binding)*">
            <xsl:for-each select="$tree//java-lineage[@source-uri != '' and @domain != '']">
                <xsl:variable name="domain" as="xs:string" select="fn:norm(@domain)"/>
                <xsl:variable name="source-uri" as="xs:string" select="normalize-space(@source-uri)"/>
                <xsl:variable name="java-flow-candidates" as="xs:string*"
                              select="(
                                $source-uri || 'direct-flow.' || $domain || '.xml',
                                $source-uri || $domain || '.seed.xml'
                              )"/>
                <xsl:for-each select="$java-flow-candidates[doc-available(.)]">
                    <xsl:for-each select="doc(.)/direct-flows/java-namespaces/namespace[@prefix != '' and @package != '']">
                        <binding prefix="{@prefix}" package="{@package}"/>
                    </xsl:for-each>
                </xsl:for-each>
            </xsl:for-each>
        </xsl:variable>
        <xsl:result-document href="{$app-path}">
            <applicationcomponent name="{$name}" path="{$app-path}">
                <xsl:for-each-group select="$java-namespace-bindings" group-by="@prefix">
                    <xsl:variable name="packages" as="xs:string*" select="distinct-values(current-group()/@package ! string(.))"/>
                    <xsl:if test="count($packages) gt 1">
                        <xsl:message terminate="yes">Conflicting Java namespace prefix '{current-grouping-key()}' for app '{$name}': {string-join($packages, ', ')}</xsl:message>
                    </xsl:if>
                    <xsl:namespace name="{current-grouping-key()}" select="'java:' || $packages[1]"/>
                </xsl:for-each-group>
                <xsl:copy-of select="@*,doc,properties"/>
                <xsl:apply-templates select="$tree" mode="post-process"/>
            </applicationcomponent>
        </xsl:result-document>
    </xsl:template>
    <xsl:template match="applicationcomponent"/>

    <!--
     Handle manual defined tables
    -->
    <xsl:template match="tables">
        <xsl:element name="{local-name(.)}">
            <xsl:attribute name="class">manual-entry</xsl:attribute>
            <xsl:apply-templates select="@*|node()"/>
        </xsl:element>
    </xsl:template>

    <!--
    Handle calls to procedures
    -->
    <xsl:template match="calls">
        <xsl:variable name="db" select="ancestor::database[1]/@name"/>
        <!-- <xsl:sequence select="fn:emit-calls($db,self::calls)"/> -->
    </xsl:template>



    <!--
    Merge multiple database entries with same name
    -->
    <xsl:template match="applicationcomponent[app]" mode="post-process">
        <xsl:element name="{local-name(.)}">
            <xsl:copy-of select="@*"/>
            <xsl:for-each-group select="database" group-by="@name">
                <xsl:sort select="current-grouping-key()"/>
                <database name="{current-grouping-key()}">
                    <xsl:apply-templates select="current-group()/calls" mode="post-process"/>
                    <xsl:apply-templates select="current-group()/events" mode="post-process"/>
                    <xsl:apply-templates select="current-group()/*[not(self::events or self::calls)]" mode="post-process"/>
                </database>
            </xsl:for-each-group>
        </xsl:element>
    </xsl:template>

    <!--
    Dedup adjacent multiple calls
    -->
    <xsl:template match="calls[call]" mode="post-process">
        <xsl:variable name="calls" select="call"/>
        <xsl:copy>
            <xsl:copy-of select="@*"/>
            <xsl:for-each-group group-adjacent="@name" select="$calls">
                <xsl:copy select="current-group()[1]">
                    <xsl:copy-of select="@*"/>
                    <xsl:if test="count(current-group()) gt 1">
                        <xsl:attribute name="count" select="count(current-group())"/>
                    </xsl:if>
                    <xsl:apply-templates select="current-group()[1]/node()" mode="post-process"/>
                </xsl:copy>
            </xsl:for-each-group>
        </xsl:copy>
    </xsl:template>

    <!--
    Default rules when specific rules not match
    -->
    <xsl:template match="l:referenced-tables" mode="#all">
        <tables>
            <xsl:apply-templates select="@*|node()" mode="#current"/>
        </tables>
    </xsl:template>

    <xsl:template match="r:to[string-length(@name)=0 or not(r:from)]"/>
    <xsl:template match="r:from[string-length(@name)=0]"/>


    <xsl:template match="m:*|l:*" mode="#all">
        <!-- move from other name space to default name space -->
        <xsl:element name="{local-name(.)}">
            <xsl:apply-templates select="@*|node()"/>
        </xsl:element>
    </xsl:template>

    <xsl:template match="@*|node()" mode="#all">
        <xsl:copy>
            <xsl:apply-templates select="@*|node()" mode="#current"/>
        </xsl:copy>
    </xsl:template>

    <xsl:variable name="schema-names" as="xs:string*" select="()"/>
    <xsl:variable name="call-tree-map" as="map(*)" select="map{}"/>
    <xsl:variable name="procedure-map" as="map(*)" select="map{}"/>
    <xsl:variable name="table-map" as="map(*)" select="map{}"/>
    <xsl:variable name="vde-config" as="node()*" select="()"/>
    <!--
     Functions
     -->
    <xsl:function name="fn:config">
        <xsl:param name="part"/>
        <xsl:variable name="uri" select="$work-uri || '/configuration/' || $part"/>
        <xsl:message>fn:config({$uri})</xsl:message>
        <xsl:sequence select="doc($uri)/*"/>
    </xsl:function>
    <xsl:function name="fn:res">
        <xsl:param name="db"/>
        <xsl:param name="res"/>
        <xsl:variable name="doc-base" select="$work-uri || '/lineage/' || $res || '.' || $db"/>
        <xsl:choose>
            <xsl:when test="doc-available($doc-base || '.xml')">
                <xsl:message>loading: {$doc-base}.xml</xsl:message>
                <xsl:sequence select="doc($doc-base || '.xml')/*"/>
            </xsl:when>
            <xsl:when test="doc-available($doc-base || '.xir')">
                <xsl:message>loading: {$doc-base}.xir</xsl:message>
                <xsl:sequence select="doc($doc-base || '.xir')/*"/>
            </xsl:when>
            <xsl:otherwise>
                <xsl:message>not available: {$doc-base} (xml or xir)</xsl:message>
            </xsl:otherwise>
        </xsl:choose>
    </xsl:function>
    <xsl:function name="fn:map-res" as="map(*)">
        <xsl:param name="res"/>
        <xsl:param name="schema-names"/>
        <xsl:map>
            <xsl:for-each select="$schema-names">
                <xsl:variable name="map-value" select="fn:res(.,$res)"/>
                <xsl:if test="not(empty($map-value))">
                    <xsl:map-entry key="." select="$map-value"/>
                </xsl:if>
            </xsl:for-each>
        </xsl:map>
    </xsl:function>
    <xsl:function name="fn:norm" as="xs:string">
        <xsl:param name="value" as="xs:string?"/>
        <xsl:sequence select="lower-case(normalize-space($value))"/>
    </xsl:function>
    <xsl:function name="fn:java-flow-uri" as="xs:string">
        <xsl:param name="domain" as="xs:string?"/>
        <xsl:variable name="normalized-domain" select="fn:norm($domain)"/>
        <xsl:variable name="trimmed-work-uri" select="replace($work-uri,'/+$','/')"/>
        <xsl:variable name="java-base-uri"
                      select="
                        if (contains($trimmed-work-uri,'/6.stitch/'))
                        then replace($trimmed-work-uri,'/6\.stitch/','/3.direct-flow/java/')
                        else $trimmed-work-uri || '../3.direct-flow/java/'
                      "/>
        <xsl:sequence
                select="if ($normalized-domain eq '')
                        then ''
                        else $java-base-uri || $normalized-domain || '/'"/>
    </xsl:function>
    <xsl:function name="fn:java-expand-class" as="xs:string">
        <xsl:param name="flow" as="element(direct-flow)"/>
        <xsl:param name="value" as="item()?"/>
        <xsl:variable name="class-value" as="xs:string" select="normalize-space(string($value))"/>
        <xsl:choose>
            <xsl:when test="$class-value = '' or starts-with($class-value, '__unresolved__.') or not(contains($class-value, ':'))">
                <xsl:sequence select="$class-value"/>
            </xsl:when>
            <xsl:otherwise>
                <xsl:variable name="prefix" as="xs:string" select="substring-before($class-value, ':')"/>
                <xsl:variable name="simple-name" as="xs:string" select="substring-after($class-value, ':')"/>
                <xsl:variable name="pkg" as="xs:string"
                              select="normalize-space(string((root($flow)/direct-flows/java-namespaces/namespace[@prefix = $prefix]/@package)[1]))"/>
                <xsl:sequence select="if ($pkg != '' and $simple-name != '') then concat($pkg, '.', $simple-name) else $class-value"/>
            </xsl:otherwise>
        </xsl:choose>
    </xsl:function>
    <xsl:function name="fn:java-class-fqn" as="xs:string">
        <xsl:param name="flow" as="element(direct-flow)"/>
        <xsl:param name="compact-value" as="item()?"/>
        <xsl:param name="legacy-fqn" as="item()?"/>
        <xsl:variable name="legacy" as="xs:string" select="normalize-space(string($legacy-fqn))"/>
        <xsl:sequence select="if ($legacy != '') then $legacy else fn:java-expand-class($flow, $compact-value)"/>
    </xsl:function>
    <xsl:function name="fn:select-java-flows" as="element(direct-flow)*">
        <xsl:param name="java-direct-flows" as="element(direct-flow)*"/>
        <xsl:param name="entrypoint-selectors" as="xs:string*"/>
        <xsl:param name="prefix-selectors" as="xs:string*"/>
        <xsl:variable name="effective-prefix-selectors" as="xs:string*"
                      select="distinct-values(
                        for $prefix in $prefix-selectors
                        return (
                          $prefix,
                          if ($prefix = 'com.ing.vortex.vre') then 'com.ing.itrf.riskengine' else ()
                        )
                      )"/>
        <xsl:variable name="matched" as="element(direct-flow)*">
            <xsl:for-each select="$java-direct-flows">
                <xsl:variable name="source-class" as="xs:string" select="fn:norm(fn:java-class-fqn(., @source, @source-fqn))"/>
                <xsl:variable name="target-class" as="xs:string" select="fn:norm(fn:java-class-fqn(., @target, @target-fqn))"/>
                <xsl:variable name="entrypoint-match" as="xs:boolean"
                              select="some $selector in $entrypoint-selectors satisfies
                              ($source-class = $selector
                               or $target-class = $selector
                               or ends-with($source-class, concat('.', $selector))
                               or ends-with($target-class, concat('.', $selector)))"/>
                <xsl:variable name="prefix-match" as="xs:boolean"
                              select="some $prefix in $effective-prefix-selectors satisfies
                              (starts-with($source-class, $prefix) or starts-with($target-class, $prefix))"/>
                <xsl:if test="$entrypoint-match or $prefix-match">
                    <xsl:sequence select="."/>
                </xsl:if>
            </xsl:for-each>
        </xsl:variable>
        <xsl:sequence select="$matched"/>
    </xsl:function>


    <xsl:function name="fn:emit-calls">
        <xsl:param name="db"/>
        <xsl:param name="calls"/>
        <xsl:sequence select="()"/>
    </xsl:function>


    <xsl:template match="java-lineage">
        <xsl:variable name="domain" as="xs:string" select="fn:norm((@domain, @source, 'vre')[1])"/>
        <xsl:variable name="is-first-domain-instance" as="xs:boolean"
                      select="empty(
                        ancestor::database[1]/preceding-sibling::database
                          /java-lineage[fn:norm((@domain, @source, 'vre')[1]) = $domain]
                      )"/>
        <xsl:variable name="operational-schema" as="xs:string" select="fn:norm(ancestor::database[1]/@name)"/>
        <xsl:variable name="java-flow-dir-uri" as="xs:string" select="fn:java-flow-uri($domain)"/>
        <xsl:variable name="java-flow-candidates" as="xs:string*"
                      select="(
                      $java-flow-dir-uri || 'direct-flow.' || $domain || '.xml',
                      $java-flow-dir-uri || $domain || '.seed.xml'
                      )"/>
        <xsl:variable name="java-direct-flows" as="element(direct-flow)*"
                      select="for $uri in $java-flow-candidates[doc-available(.)]
                      return doc($uri)/direct-flows/direct-flow"/>
        <xsl:variable name="legacy-entrypoint-selectors" as="xs:string*" select="entrypoint/@class ! fn:norm(.)"/>
        <xsl:variable name="legacy-prefix-selectors" as="xs:string*" select="class-prefix/@value ! fn:norm(.)"/>
        <xsl:variable name="legacy-flows" as="element(direct-flow)*"
                      select="fn:select-java-flows($java-direct-flows, $legacy-entrypoint-selectors, $legacy-prefix-selectors)"/>
        <xsl:variable name="static-entrypoint-selectors" as="xs:string*" select="static/entrypoint/@class ! fn:norm(.)"/>
        <xsl:variable name="static-prefix-selectors" as="xs:string*" select="static/class-prefix/@value ! fn:norm(.)"/>
        <xsl:variable name="operational-entrypoint-selectors" as="xs:string*" select="operational/entrypoint/@class ! fn:norm(.)"/>
        <xsl:variable name="operational-prefix-selectors" as="xs:string*" select="operational/class-prefix/@value ! fn:norm(.)"/>
        <xsl:variable name="static-flows" as="element(direct-flow)*"
                      select="fn:select-java-flows($java-direct-flows, $static-entrypoint-selectors, $static-prefix-selectors)"/>
        <xsl:variable name="operational-flows" as="element(direct-flow)*"
                      select="fn:select-java-flows($java-direct-flows, $operational-entrypoint-selectors, $operational-prefix-selectors)"/>
        <xsl:variable name="operational-flows-effective" as="element(direct-flow)*"
                      select="if ($is-first-domain-instance) then $operational-flows else ()"/>
        <java-lineage domain="{$domain}"
                      source-uri="{$java-flow-dir-uri}"
                      db-schema="{$operational-schema}">
            <xsl:choose>
                <xsl:when test="static or operational">
                    <role name="static"
                          schema="sdp"
                          selector-count="{count($static-entrypoint-selectors) + count($static-prefix-selectors)}"
                          flow-count="{count($static-flows)}">
                        <xsl:copy-of select="static/(entrypoint|class-prefix)"/>
                        <flows>
                            <xsl:for-each-group select="$static-flows" group-by="@id">
                                <xsl:sort select="@id"/>
                                <xsl:copy-of select="current-group()[1]"/>
                            </xsl:for-each-group>
                        </flows>
                    </role>
                    <role name="operational"
                          schema="{$operational-schema}"
                          selector-count="{count($operational-entrypoint-selectors) + count($operational-prefix-selectors)}"
                          flow-count="{count($operational-flows-effective)}">
                        <xsl:copy-of select="operational/(entrypoint|class-prefix)"/>
                        <flows>
                            <xsl:for-each-group select="$operational-flows-effective" group-by="@id">
                                <xsl:sort select="@id"/>
                                <xsl:copy-of select="current-group()[1]"/>
                            </xsl:for-each-group>
                        </flows>
                    </role>
                </xsl:when>
                <xsl:otherwise>
                    <xsl:variable name="legacy-flows-effective" as="element(direct-flow)*"
                                  select="if ($is-first-domain-instance) then $legacy-flows else ()"/>
                    <role name="operational"
                          schema="{$operational-schema}"
                          selector-count="{count($legacy-entrypoint-selectors) + count($legacy-prefix-selectors)}"
                          flow-count="{count($legacy-flows-effective)}">
                        <xsl:copy-of select="entrypoint|class-prefix"/>
                        <flows>
                            <xsl:for-each-group select="$legacy-flows-effective" group-by="@id">
                                <xsl:sort select="@id"/>
                                <xsl:copy-of select="current-group()[1]"/>
                            </xsl:for-each-group>
                        </flows>
                    </role>
                </xsl:otherwise>
            </xsl:choose>
        </java-lineage>
    </xsl:template>



    <!-- end custom tags -->

</xsl:stylesheet>
