<xsl:stylesheet version="3.0"
                xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
                xmlns:xs="http://www.w3.org/2001/XMLSchema"
                xmlns:f="urn:java-flow-merge"
                exclude-result-prefixes="xs f"
                expand-text="yes">
    <xsl:output method="xml" indent="yes" encoding="UTF-8"/>
    <xsl:strip-space elements="*"/>
    <xsl:mode on-no-match="shallow-skip"/>

    <xsl:param name="input-uri" as="xs:string?" select="''"/>

    <xsl:function name="f:as-uri" as="xs:string">
        <xsl:param name="path" as="xs:string"/>
        <xsl:sequence select="
            if (matches($path, '^[A-Za-z][A-Za-z0-9+.-]*:'))
            then $path
            else string(resolve-uri($path, 'file:///'))"/>
    </xsl:function>

    <xsl:function name="f:collection-uri" as="xs:string">
        <xsl:param name="context" as="node()"/>
        <xsl:param name="dir" as="xs:string?"/>
        <xsl:variable name="provided-uri" as="xs:string"
                      select="if (normalize-space($dir)) then normalize-space($dir) else ''"/>
        <xsl:choose>
            <xsl:when test="contains($provided-uri, '?select=')">
                <xsl:sequence select="$provided-uri"/>
            </xsl:when>
            <xsl:when test="$provided-uri ne ''">
                <xsl:variable name="base-uri" as="xs:string" select="f:as-uri($provided-uri)"/>
                <xsl:variable name="dir-uri" as="xs:string"
                              select="if (ends-with($base-uri, '/')) then $base-uri else $base-uri || '/'"/>
                <xsl:sequence select="$dir-uri || '?select=*.xir;recurse=yes;on-error=ignore'"/>
            </xsl:when>
            <xsl:otherwise>
                <xsl:variable name="base-dir-uri" as="xs:string"
                              select="replace(string(base-uri($context)), '[^/]+$', '')"/>
                <xsl:variable name="dir-uri" as="xs:string"
                              select="if (ends-with($base-dir-uri, '/')) then $base-dir-uri else $base-dir-uri || '/'"/>
                <xsl:sequence select="$dir-uri || '?select=*.xir;recurse=yes;on-error=ignore'"/>
            </xsl:otherwise>
        </xsl:choose>
    </xsl:function>

    <xsl:template match="/">
        <xsl:variable name="docs" as="document-node()*" select="collection(f:collection-uri(., $input-uri))"/>
        <xsl:variable name="graphs" as="element(flow-graph)*" select="$docs/flow-graph"/>
        <xsl:variable name="allEdges" as="element(edge)*" select="$graphs/edges/edge"/>

        <flow-graph-merged>
            <nodes>
                <xsl:for-each-group select="$graphs/nodes/node" group-by="string(@id)">
                    <xsl:sort select="current-grouping-key()"/>
                    <node id="{current-grouping-key()}" kind="{if (some $k in current-group()/@kind satisfies $k = 'source') then 'source' else 'class'}"/>
                </xsl:for-each-group>
            </nodes>
            <edges>
                <xsl:for-each-group select="$allEdges"
                                    group-by="string-join((@kind, @source, @target, @method, @via), '|')">
                    <xsl:sort select="current-group()[1]/@kind"/>
                    <xsl:sort select="current-group()[1]/@source"/>
                    <xsl:sort select="current-group()[1]/@target"/>
                    <xsl:variable name="sample" as="element(edge)" select="current-group()[1]"/>
                    <edge kind="{$sample/@kind}"
                          source="{$sample/@source}"
                          target="{$sample/@target}"
                          method="{$sample/@method}"
                          via="{$sample/@via}"
                          occurrences="{count(current-group())}">
                        <sources>
                            <xsl:for-each-group select="current-group()/ancestor::flow-graph" group-by="string(@source)">
                                <xsl:sort select="current-grouping-key()"/>
                                <source file="{current-grouping-key()}"/>
                            </xsl:for-each-group>
                        </sources>
                        <lines>
                            <xsl:for-each select="distinct-values(current-group()/@line[normalize-space(.) ne ''])">
                                <xsl:sort select="number(.)"/>
                                <line n="{.}"/>
                            </xsl:for-each>
                        </lines>
                    </edge>
                </xsl:for-each-group>
            </edges>
            <meta sourceCount="{count($docs)}"
                  classCount="{count(distinct-values($graphs/@class))}"
                  nodeCount="{count(distinct-values($graphs/nodes/node/@id))}"
                  rawEdgeCount="{count($allEdges)}"
                  edgeCount="{count(for $g in distinct-values($allEdges ! string-join((@kind, @source, @target, @method, @via), '|')) return $g)}"/>
        </flow-graph-merged>
    </xsl:template>
</xsl:stylesheet>
